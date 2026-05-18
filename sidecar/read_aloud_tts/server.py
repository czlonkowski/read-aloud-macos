"""FastAPI sidecar exposing an OpenAI-compatible /v1/audio/speech endpoint.

Routes by the `model` field of the request body:
- "kokoro" → Kokoro-82M (English, MLX)
- "piper"  → Piper TTS (Polish via Justyna voice, ONNX)

The response is streaming 16-bit PCM at 24 kHz (`response_format=pcm`) or a
single WAV file (`response_format=wav`). The Swift client always uses PCM.
"""

from __future__ import annotations

import asyncio
import io
import logging
from typing import AsyncIterator, Literal

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import (
    HOST,
    PORT,
    KOKORO_IDLE_UNLOAD_SECONDS,
    PIPER_IDLE_UNLOAD_SECONDS,
    PIPER_VOICES,
    PIPER_VOICES_DIR,
    KOKORO_VOICES,
)
from .engines.kokoro_engine import KokoroEngine
from .engines.piper_engine import PiperEngine


log = logging.getLogger("read_aloud_tts")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


kokoro = KokoroEngine()
piper = PiperEngine(voices_dir=PIPER_VOICES_DIR)

app = FastAPI(title="Read Aloud TTS", version="0.2.0")


class SpeechRequest(BaseModel):
    model: Literal["kokoro", "piper"]
    voice: str
    input: str = Field(min_length=1, max_length=8_000)
    stream: bool = True
    response_format: Literal["pcm", "wav"] = "pcm"
    sample_rate: int = 24_000


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse(
        {
            "ok": True,
            "version": "0.2.0",
            "kokoro_loaded": kokoro._model is not None,
            "piper_loaded": piper.loaded,
        }
    )


@app.get("/v1/voices")
async def voices() -> JSONResponse:
    return JSONResponse(
        {
            "kokoro": [v.__dict__ for v in KOKORO_VOICES],
            "piper": [v.__dict__ for v in PIPER_VOICES],
        }
    )


@app.post("/v1/warmup")
async def warmup() -> JSONResponse:
    """Eagerly load both engines. Idempotent — re-calling is a no-op."""
    await kokoro._ensure_loaded()
    # Warm the default Piper voice (Justyna).
    if PIPER_VOICES:
        v = PIPER_VOICES[0]
        if v.voice_file:
            await piper._ensure_loaded(v.id, v.voice_file)
    return JSONResponse({"ok": True})


@app.post("/v1/audio/speech")
async def speech(req: SpeechRequest):
    if req.sample_rate != 24_000:
        raise HTTPException(status_code=400, detail="sample_rate must be 24000")

    if req.model == "kokoro":
        if req.voice not in {v.id for v in KOKORO_VOICES}:
            raise HTTPException(status_code=400, detail=f"Unknown Kokoro voice {req.voice}")
        audio_iter = kokoro.synth(req.input, voice=req.voice)
    else:  # piper
        match = next((v for v in PIPER_VOICES if v.id == req.voice), None)
        if match is None or not match.voice_file:
            raise HTTPException(status_code=400, detail=f"Unknown Piper voice {req.voice}")
        audio_iter = piper.synth(req.input, voice=req.voice, voice_file=match.voice_file)

    if req.response_format == "wav":
        chunks: list[np.ndarray] = []
        async for arr in audio_iter:
            chunks.append(arr)
        audio = np.concatenate(chunks) if chunks else np.zeros(0, dtype=np.float32)
        buf = io.BytesIO()
        sf.write(buf, audio, 24_000, format="WAV", subtype="PCM_16")
        buf.seek(0)
        return StreamingResponse(buf, media_type="audio/wav")

    return StreamingResponse(_pcm_stream(audio_iter), media_type="audio/pcm")


async def _pcm_stream(audio_iter: AsyncIterator[np.ndarray]) -> AsyncIterator[bytes]:
    async for arr in audio_iter:
        pcm16 = np.clip(arr, -1.0, 1.0)
        pcm16 = (pcm16 * 32_767.0).astype(np.int16)
        yield pcm16.tobytes()


@app.on_event("startup")
async def _on_startup() -> None:
    async def warmup_task() -> None:
        try:
            log.info("eager warmup: loading Kokoro…")
            await kokoro._ensure_loaded()
            if PIPER_VOICES and PIPER_VOICES[0].voice_file:
                log.info("eager warmup: loading Piper Justyna…")
                await piper._ensure_loaded(PIPER_VOICES[0].id, PIPER_VOICES[0].voice_file)
            log.info("eager warmup: done")
        except Exception:
            log.exception("eager warmup failed")

    async def unloader() -> None:
        while True:
            await asyncio.sleep(60)
            kokoro.maybe_unload(KOKORO_IDLE_UNLOAD_SECONDS)
            piper.maybe_unload(PIPER_IDLE_UNLOAD_SECONDS)

    asyncio.create_task(warmup_task())
    asyncio.create_task(unloader())


def run() -> None:
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT, log_level="info", workers=1)


if __name__ == "__main__":
    run()
