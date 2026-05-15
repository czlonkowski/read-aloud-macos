"""MLX-Audio Kokoro adapter (English).

Streams 24kHz Float32 audio chunks. The Swift client converts to int16 PCM
on the wire (see `response_format=pcm` in the OpenAI-compatible payload).
"""

from __future__ import annotations

import asyncio
import time
from typing import AsyncIterator

import numpy as np


class KokoroEngine:
    """Lazy-loaded Kokoro pipeline. Uses MLX-Audio under the hood."""

    SAMPLE_RATE = 24_000

    def __init__(self) -> None:
        self._pipeline = None
        self._last_used: float = 0.0
        self._lock = asyncio.Lock()

    async def synth(self, text: str, voice: str) -> AsyncIterator[np.ndarray]:
        """Yield Float32 numpy arrays at 24kHz."""
        await self._ensure_loaded()
        self._last_used = time.monotonic()
        loop = asyncio.get_running_loop()
        # MLX-Audio's API is synchronous; offload to a worker thread so we
        # don't block the FastAPI event loop.
        audio = await loop.run_in_executor(None, self._generate, text, voice)
        # Yield in ~200ms chunks so the client can start playback before the
        # whole tensor is rendered.
        chunk = self.SAMPLE_RATE // 5
        for i in range(0, len(audio), chunk):
            yield np.ascontiguousarray(audio[i : i + chunk], dtype=np.float32)

    def maybe_unload(self, idle_seconds: float) -> None:
        if self._pipeline is not None and time.monotonic() - self._last_used > idle_seconds:
            self._pipeline = None

    async def _ensure_loaded(self) -> None:
        if self._pipeline is not None:
            return
        async with self._lock:
            if self._pipeline is not None:
                return
            # Import lazily so the server starts even if mlx-audio isn't yet
            # installed (you'll see a clear error only when the user actually
            # requests Kokoro speech).
            from mlx_audio.tts.generate import generate_audio  # type: ignore

            self._generate_audio = generate_audio
            self._pipeline = True  # sentinel: the function is importable

    def _generate(self, text: str, voice: str) -> np.ndarray:
        # mlx_audio.tts.generate.generate_audio returns numpy float32 audio.
        # Voice IDs follow Kokoro's "<gender><region>_<name>" convention
        # (e.g. "af_heart").
        return self._generate_audio(
            text=text,
            model_path="mlx-community/Kokoro-82M-bf16",
            voice=voice,
            sample_rate=self.SAMPLE_RATE,
        )
