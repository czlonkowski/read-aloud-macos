# Architecture

This is a short reference. The full implementation plan is in `~/.claude/plans/i-want-us-to-wild-shannon.md`.

## Two-process design

```
┌──────────────────────────────────────────────────────────────┐
│  ReadAloud.app  (Swift, menu-bar only, ad-hoc signed)        │
│   • KeyboardShortcuts.onKeyDown(.readSelection)              │
│   • SelectionService.capture() → text + bundleID             │
│   • LanguageRouter → "en" | "pl" (per-app override wins)     │
│   • TTSCoordinator routes by language preference             │
│       - apple → AppleEngine (AVSpeechSynthesizer)            │
│       - sidecar → SidecarEngine streams PCM from :8000       │
│   • StreamingPlayer (AVAudioEngine) plays gaplessly          │
└──────────────────────┬───────────────────────────────────────┘
                       │ HTTP POST /v1/audio/speech (stream PCM)
┌──────────────────────▼───────────────────────────────────────┐
│  read-aloud-sidecar  (Python, launchd agent, OnDemand)       │
│   • FastAPI on 127.0.0.1:8000                                │
│   • Routes by `model`:                                       │
│       - "kokoro"     → MLX-Audio Kokoro (EN, ~330MB, MLX)    │
│       - "chatterbox" → Chatterbox Multilingual (PL, ~1GB)    │
│   • Sentence-level streaming PCM 24kHz int16                 │
│   • Idle-unload after 5 min                                  │
└───────────────────────────────────────────────────────────────┘
```

## Why a sidecar instead of pure Swift?

The Polish neural TTS state of the art in 2026 lives in PyTorch (Chatterbox Multilingual, Resemble AI). No production-grade Polish neural model is available as a pure-Swift MLX port today. Kokoro **does** have a Swift port (KokoroSwift / mlx-audio Swift target) — but Kokoro doesn't speak Polish. To get high-quality Polish output we'd need PyTorch anyway, so we host both engines in one Python process and let Swift talk to them over HTTP. This also makes A/B testing future models trivial.

## Engineering patterns reused from Meeting Transcriber

- `@MainActor @Observable AppState` as the central coordinator.
- Per-feature JSON stores under `~/Library/Application Support/ReadAloud/`.
- XcodeGen project (`project.yml`).
- Ad-hoc signing, hardened runtime ON, sandbox OFF.
- Personal reinstall script using osascript + lsregister.

## Engineering patterns not carried over

- Background processing queue (`ProcessingJob`) — TTS is per-utterance and cancellable, not a long-running job, so we use `Task<Void, Never>` with cancellation instead of a serial drain.
- MCP server — there's no persisted artifact to query. May add a `speak_text` tool in a later version.
- Multi-window app shell — this is a menu-bar-only utility (`LSUIElement = true`).
- WhisperKit / FluidAudio / MLX-Swift-LM dependencies — none of these are needed because no inference happens in-process.
