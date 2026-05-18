"""Chatterbox Multilingual adapter (Polish).

Resemble AI's Chatterbox runs on PyTorch + MPS on Apple Silicon. We resample
its native sample rate to 24kHz so the client can use a single AVAudioFormat.
"""

from __future__ import annotations

import asyncio
import time
from pathlib import Path
from typing import AsyncIterator

import numpy as np


class ChatterboxEngine:
    SAMPLE_RATE = 24_000

    def __init__(self, voices_dir: Path) -> None:
        self._model = None
        self._native_sr: int | None = None
        self._last_used: float = 0.0
        self._lock = asyncio.Lock()
        self._voices_dir = voices_dir

    async def synth(
        self,
        text: str,
        voice: str,
        reference_path: str | None,
    ) -> AsyncIterator[np.ndarray]:
        await self._ensure_loaded()
        self._last_used = time.monotonic()
        loop = asyncio.get_running_loop()
        audio, sr = await loop.run_in_executor(
            None,
            self._generate,
            text,
            voice,
            reference_path,
        )
        if sr != self.SAMPLE_RATE:
            audio = self._resample(audio, sr, self.SAMPLE_RATE)
        chunk = self.SAMPLE_RATE // 5
        for i in range(0, len(audio), chunk):
            yield np.ascontiguousarray(audio[i : i + chunk], dtype=np.float32)

    def maybe_unload(self, idle_seconds: float) -> None:
        if self._model is not None and time.monotonic() - self._last_used > idle_seconds:
            self._model = None
            self._native_sr = None

    async def _ensure_loaded(self) -> None:
        if self._model is not None:
            return
        async with self._lock:
            if self._model is not None:
                return
            from chatterbox.mtl_tts import ChatterboxMultilingualTTS  # type: ignore
            import torch  # type: ignore

            device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
            self._torch = torch
            loop = asyncio.get_running_loop()
            self._model = await loop.run_in_executor(
                None,
                lambda: ChatterboxMultilingualTTS.from_pretrained(device=device),
            )
            self._native_sr = int(getattr(self._model, "sr", 24_000))

    def _generate(
        self,
        text: str,
        voice: str,
        reference_path: str | None,
    ) -> tuple[np.ndarray, int]:
        ref = self._voices_dir / (reference_path or f"{voice}.wav")
        kwargs: dict = {"text": text, "language_id": "pl"}
        if ref.exists():
            kwargs["audio_prompt_path"] = str(ref)
        # Chatterbox returns a torch tensor.
        wav = self._model.generate(**kwargs)
        if hasattr(wav, "detach"):
            wav = wav.detach().cpu().numpy()
        wav = np.asarray(wav, dtype=np.float32).squeeze()
        return wav, self._native_sr or 24_000

    @staticmethod
    def _resample(audio: np.ndarray, src_sr: int, dst_sr: int) -> np.ndarray:
        if src_sr == dst_sr:
            return audio
        ratio = dst_sr / src_sr
        n = int(round(len(audio) * ratio))
        x_old = np.linspace(0.0, 1.0, num=len(audio), endpoint=False)
        x_new = np.linspace(0.0, 1.0, num=n, endpoint=False)
        return np.interp(x_new, x_old, audio).astype(np.float32)
