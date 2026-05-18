"""Sidecar runtime configuration: model IDs, voice library, idle-unload window."""

from __future__ import annotations

from dataclasses import dataclass


HOST = "127.0.0.1"
PORT = 8000

# Drop loaded models from memory after this many seconds idle. Kokoro (~330 MB)
# warms up in <1 s so reloading is cheap. Chatterbox (~1 GB) takes ~30 s to
# load, so a generous window matters more than the memory savings on a 32 GB
# machine. Override per-engine below.
KOKORO_IDLE_UNLOAD_SECONDS = 600
CHATTERBOX_IDLE_UNLOAD_SECONDS = 3 * 3600  # effectively "until the sidecar restarts"


@dataclass(frozen=True)
class VoiceEntry:
    id: str
    display_name: str
    language: str  # "en" or "pl"
    # For Chatterbox: path (relative to sidecar/voices/) of the reference WAV.
    reference_path: str | None = None


# v0.1 voice library. The Chatterbox references are added by `install-sidecar.sh`
# (or copied manually); Kokoro voices are baked into the model.
KOKORO_VOICES: list[VoiceEntry] = [
    VoiceEntry(id="af_heart",   display_name="Heart",   language="en"),
    VoiceEntry(id="af_bella",   display_name="Bella",   language="en"),
    VoiceEntry(id="am_michael", display_name="Michael", language="en"),
    VoiceEntry(id="am_adam",    display_name="Adam",    language="en"),
]

CHATTERBOX_VOICES: list[VoiceEntry] = [
    VoiceEntry(
        id="pl_speaker_01",
        display_name="Polish Reference 1",
        language="pl",
        reference_path="pl_speaker_01.wav",
    ),
    VoiceEntry(
        id="pl_speaker_02",
        display_name="Polish Reference 2",
        language="pl",
        reference_path="pl_speaker_02.wav",
    ),
]


def all_voices() -> list[VoiceEntry]:
    return KOKORO_VOICES + CHATTERBOX_VOICES
