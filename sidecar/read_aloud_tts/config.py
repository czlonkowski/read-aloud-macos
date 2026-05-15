"""Sidecar runtime configuration: model IDs, voice library, idle-unload window."""

from __future__ import annotations

from dataclasses import dataclass


HOST = "127.0.0.1"
PORT = 8000

# Drop loaded models from memory after this many seconds idle. Kokoro is small
# (~330 MB) so 5 minutes is fine; Chatterbox is ~1 GB so we want to release it
# when the user walks away.
IDLE_UNLOAD_SECONDS = 300


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
