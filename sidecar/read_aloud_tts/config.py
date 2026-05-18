"""Sidecar runtime configuration: model IDs, voice library, idle-unload window."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


HOST = "127.0.0.1"
PORT = 8000

# Drop loaded models from memory after this many seconds idle. Kokoro (~330 MB)
# warms up in <1 s so reloading is cheap. Piper (~60 MB) is even smaller and
# loads in ~200 ms; we still keep both warm by default to avoid any wait on
# the first hotkey press.
KOKORO_IDLE_UNLOAD_SECONDS = 600
PIPER_IDLE_UNLOAD_SECONDS = 600

# Piper voice files live outside the repo because they're 60 MB ONNX models.
# install-sidecar.sh downloads them to this location.
PIPER_VOICES_DIR = Path(
    os.path.expanduser("~/Library/Application Support/ReadAloud/piper-voices")
)


@dataclass(frozen=True)
class VoiceEntry:
    id: str
    display_name: str
    language: str  # "en" or "pl"
    # For Piper: filename (relative to PIPER_VOICES_DIR) of the .onnx model.
    voice_file: str | None = None


KOKORO_VOICES: list[VoiceEntry] = [
    VoiceEntry(id="af_heart",   display_name="Heart",   language="en"),
    VoiceEntry(id="af_bella",   display_name="Bella",   language="en"),
    VoiceEntry(id="am_michael", display_name="Michael", language="en"),
    VoiceEntry(id="am_adam",    display_name="Adam",    language="en"),
]

PIPER_VOICES: list[VoiceEntry] = [
    VoiceEntry(
        id="pl_justyna",
        display_name="Justyna",
        language="pl",
        voice_file="pl_PL-justyna_wg_glos-medium.onnx",
    ),
]


def all_voices() -> list[VoiceEntry]:
    return KOKORO_VOICES + PIPER_VOICES
