"""Piper TTS adapter (Polish).

Runs ONNX phoneme-to-audio inference at ~30× real-time. Resamples Piper's
22.05 kHz native output to 24 kHz so the client sees a single sample rate
across all sidecar engines.
"""

from __future__ import annotations

import asyncio
import time
from pathlib import Path
from typing import AsyncIterator

import numpy as np


class PiperEngine:
    SAMPLE_RATE = 24_000

    def __init__(self, voices_dir: Path) -> None:
        self._voices_dir = voices_dir
        # voice_id -> PiperVoice instance.
        self._voices: dict[str, object] = {}
        self._last_used: float = 0.0
        self._load_lock = asyncio.Lock()
        self._inference_lock = asyncio.Lock()

    async def synth(self, text: str, voice: str, voice_file: str) -> AsyncIterator[np.ndarray]:
        await self._ensure_loaded(voice, voice_file)
        self._last_used = time.monotonic()
        loop = asyncio.get_running_loop()
        async with self._inference_lock:
            audio, native_sr = await loop.run_in_executor(
                None,
                self._generate,
                voice,
                text,
            )
        if native_sr != self.SAMPLE_RATE:
            audio = self._resample(audio, native_sr, self.SAMPLE_RATE)
        chunk = self.SAMPLE_RATE // 5
        for i in range(0, len(audio), chunk):
            yield np.ascontiguousarray(audio[i : i + chunk], dtype=np.float32)

    def maybe_unload(self, idle_seconds: float) -> None:
        if self._voices and time.monotonic() - self._last_used > idle_seconds:
            self._voices.clear()

    @property
    def loaded(self) -> bool:
        return bool(self._voices)

    async def _ensure_loaded(self, voice_id: str, voice_file: str) -> None:
        if voice_id in self._voices:
            return
        async with self._load_lock:
            if voice_id in self._voices:
                return
            from piper import PiperVoice  # type: ignore

            voice_path = self._voices_dir / voice_file
            if not voice_path.exists():
                raise FileNotFoundError(
                    f"Piper voice not installed: {voice_path}. "
                    "Re-run scripts/install-sidecar.sh."
                )
            loop = asyncio.get_running_loop()
            self._voices[voice_id] = await loop.run_in_executor(
                None,
                lambda: PiperVoice.load(str(voice_path)),
            )

    def _generate(self, voice_id: str, text: str) -> tuple[np.ndarray, int]:
        voice = self._voices[voice_id]
        pieces: list[np.ndarray] = []
        sr: int | None = None
        for chunk in voice.synthesize(text):  # type: ignore[attr-defined]
            pieces.append(np.asarray(chunk.audio_float_array, dtype=np.float32))
            sr = chunk.sample_rate
        if not pieces:
            return np.zeros(0, dtype=np.float32), sr or 22_050
        return np.concatenate(pieces), sr or 22_050

    @staticmethod
    def _resample(audio: np.ndarray, src_sr: int, dst_sr: int) -> np.ndarray:
        if src_sr == dst_sr:
            return audio
        ratio = dst_sr / src_sr
        n = int(round(len(audio) * ratio))
        x_old = np.linspace(0.0, 1.0, num=len(audio), endpoint=False)
        x_new = np.linspace(0.0, 1.0, num=n, endpoint=False)
        return np.interp(x_new, x_old, audio).astype(np.float32)
