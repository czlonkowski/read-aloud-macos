"""FastAPI sidecar exposing an OpenAI-compatible /v1/audio/speech endpoint.

Routes by the `model` field of the request body:
- "kokoro"     → Kokoro-82M (English)
- "chatterbox" → Chatterbox Multilingual (Polish)

The response is streaming 16-bit PCM at 24kHz (`response_format=pcm`) or a
single WAV file (`response_format=wav`). The Swift client always uses PCM.
"""

from __future__ import annotations

import asyncio
import io
import logging
from pathlib import Path
from typing import AsyncIterator, Literal

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel, Field

from .config import (
    HOST,
    PORT,
    IDLE_UNLOAD_SECONDS,
    CHATTERBOX_VOICES,
    KOKORO_VOICES,
    all_voices,
)
from .engines.kokoro_engine import KokoroEngine
from .engines.chatterbox_engine import ChatterboxEngine


log = logging.getLogger("read_aloud_tts")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


SIDECAR_ROOT = Path(__file__).resolve().parent.parent
VOICES_DIR = SIDECAR_ROOT / "voices"

kokoro = KokoroEngine()
chatterbox = ChatterboxEngine(voices_dir=VOICES_DIR)

app = FastAPI(title="Read Aloud TTS", version="0.1.0")


class SpeechRequest(BaseModel):
    model: Literal["kokoro", "chatterbox"]
    voice: str
    input: str = Field(min_length=1, max_length=8_000)
    stream: bool = True
    response_format: Literal["pcm", "wav"] = "pcm"
    sample_rate: int = 24_000


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"ok": True, "version": "0.1.0"})


@app.get("/v1/voices")
async def voices() -> JSONResponse:
    return JSONResponse(
        {
            "kokoro": [v.__dict__ for v in KOKORO_VOICES],
            "chatterbox": [v.__dict__ for v in CHATTERBOX_VOICES],
        }
    )


@app.post("/v1/audio/speech")
async def speech(req: SpeechRequest):
    if req.sample_rate != 24_000:
        raise HTTPException(status_code=400, detail="sample_rate must be 24000")

    if req.model == "kokoro":
        if req.voice not in {v.id for v in KOKORO_VOICES}:
            raise HTTPException(status_code=400, detail=f"Unknown Kokoro voice {req.voice}")
        audio_iter = kokoro.synth(req.input, voice=req.voice)
    else:
        match = next((v for v in CHATTERBOX_VOICES if v.id == req.voice), None)
        if match is None:
            raise HTTPException(status_code=400, detail=f"Unknown Chatterbox voice {req.voice}")
        audio_iter = chatterbox.synth(
            req.input,
            voice=req.voice,
            reference_path=match.reference_path,
        )

    if req.response_format == "wav":
        # Non-streaming WAV path: collect everything and emit one file.
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
async def _start_idle_unloader() -> None:
    async def loop() -> None:
        while True:
            await asyncio.sleep(60)
            kokoro.maybe_unload(IDLE_UNLOAD_SECONDS)
            chatterbox.maybe_unload(IDLE_UNLOAD_SECONDS)

    asyncio.create_task(loop())


def run() -> None:
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT, log_level="info", workers=1)


if __name__ == "__main__":
    run()
