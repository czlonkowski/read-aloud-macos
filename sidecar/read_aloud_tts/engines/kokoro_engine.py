"""MLX-Audio Kokoro adapter (English).

Loads `mlx-community/Kokoro-82M-bf16` lazily on first request and serves
24 kHz float32 audio. mlx-audio's `Model.generate(...)` is a synchronous
streaming generator yielding `GenerationResult` chunks; we run it in a
worker thread and forward each chunk into an `asyncio.Queue` so callers
get true streaming with low time-to-first-audio.
"""

from __future__ import annotations

import asyncio
import time
from typing import AsyncIterator

import numpy as np


KOKORO_REPO = "mlx-community/Kokoro-82M-bf16"


class KokoroEngine:
    """Lazy-loaded Kokoro pipeline. Audio is yielded chunk-by-chunk."""

    SAMPLE_RATE = 24_000

    def __init__(self) -> None:
        self._model = None
        self._last_used: float = 0.0
        self._load_lock = asyncio.Lock()
        # Serializes generate() calls — mlx-audio's Kokoro pipeline holds
        # per-language pipeline state that isn't safe to share across
        # concurrent generate() invocations.
        self._inference_lock = asyncio.Lock()

    async def synth(self, text: str, voice: str) -> AsyncIterator[np.ndarray]:
        await self._ensure_loaded()
        self._last_used = time.monotonic()
        loop = asyncio.get_running_loop()
        async with self._inference_lock:
            queue: asyncio.Queue[np.ndarray | None] = asyncio.Queue(maxsize=4)

            def producer() -> None:
                try:
                    for chunk in self._model.generate(text=text, voice=voice):
                        audio = np.asarray(chunk.audio, dtype=np.float32)
                        loop.call_soon_threadsafe(queue.put_nowait, audio)
                except Exception as exc:  # surface as terminating sentinel
                    loop.call_soon_threadsafe(queue.put_nowait, exc)  # type: ignore[arg-type]
                finally:
                    loop.call_soon_threadsafe(queue.put_nowait, None)

            fut = loop.run_in_executor(None, producer)
            try:
                while True:
                    item = await queue.get()
                    if item is None:
                        break
                    if isinstance(item, Exception):
                        raise item
                    yield item
            finally:
                await fut

    def maybe_unload(self, idle_seconds: float) -> None:
        if self._model is not None and time.monotonic() - self._last_used > idle_seconds:
            self._model = None

    async def _ensure_loaded(self) -> None:
        if self._model is not None:
            return
        async with self._load_lock:
            if self._model is not None:
                return
            from mlx_audio.tts import load_model  # type: ignore

            loop = asyncio.get_running_loop()
            self._model = await loop.run_in_executor(None, load_model, KOKORO_REPO)
