"""Read Aloud local TTS sidecar.

Exposes an OpenAI-compatible /v1/audio/speech endpoint that routes between
Kokoro (English, MLX-accelerated) and Chatterbox Multilingual (Polish,
PyTorch on MPS).
"""

__version__ = "0.1.0"
