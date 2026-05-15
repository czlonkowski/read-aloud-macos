# Read Aloud

A native macOS menu-bar utility that reads the currently-selected text aloud in any app via a global hotkey. English + Polish are both first-class.

Sister project to [meeting-transcriber-macos](../meeting-transcriber-macos): same Swift-app shell, but with a local TTS sidecar instead of an STT pipeline.

## How it works

```
Select text in any app  →  ⌥⌘R  →  Read Aloud captures selection
                              ↓
            NLLanguageRecognizer picks English or Polish
                              ↓
       ┌── Apple AVSpeechSynthesizer (Zosia / Ava / Zoe)  ─── v0.1 default
       └── Python sidecar on 127.0.0.1:8000               ─── enable in Settings
                Kokoro-82M (English, MLX)
                Chatterbox Multilingual (Polish, PyTorch+MPS)
                              ↓
              AVAudioEngine streams PCM gaplessly
```

The Swift app is signed ad-hoc (Developer ID-style) and runs **un-sandboxed** because the selection-capture chain needs to synthesise ⌘C in Electron apps. The neural sidecar is an optional `launchd` agent — until you enable it from Settings, the app uses only Apple's built-in voices.

## Setup

### Build the Swift app

Requires Xcode 16+ and `xcodegen`.

```sh
brew install xcodegen
xcodegen generate
open ReadAloud.xcodeproj
```

The first run will prompt for **Accessibility** permission (read selected text) and, in some apps, **Input Monitoring** (synthesise ⌘C). Grant both via System Settings ▸ Privacy & Security.

### Installing the sidecar (optional)

Only needed if you want Kokoro/Chatterbox quality instead of Apple's built-in voices.

```sh
brew install uv
./scripts/install-sidecar.sh
```

This sets up a Python 3.12 virtualenv at `~/Library/Application Support/ReadAloud/sidecar-venv`, registers a `launchd` agent (`com.czlonkowski.readaloud-sidecar`), and is ready to start on demand. Toggle "Enable neural sidecar" in Settings ▸ Neural to start using it.

For Polish voice cloning, drop reference WAVs into `sidecar/voices/` (see `voices/README.md`).

### Deploy locally

```sh
# Build once in Xcode (⌘B), then:
./scripts/reinstall.sh
```

Copies the Debug build to `/Applications/ReadAloud.app` and re-registers it with `lsregister`.

## Default hotkeys

| Action | Shortcut |
|---|---|
| Read selection | ⌥⌘R |
| Stop reading   | ⌥⌘. |

Remap from Settings ▸ Hotkey.

## Repository layout

```
ReadAloud/        Swift app (menu-bar only, LSUIElement=true)
  App/            entry, AppState, menu-bar UI
  Hotkey/         KeyboardShortcuts names
  Capture/        SelectedTextKit wrapper + language router
  Synthesize/     TTS coordinator, Apple engine, sidecar engine, chunker
  Audio/          AVAudioEngine PCM streamer
  Sidecar/        launchctl wrapper, healthz polling
  Storage/        JSON-backed preference stores
  Models/         domain types
  UI/             Settings tabs, voice picker, HUD
  Resources/      Info.plist, entitlements, assets

sidecar/          Python TTS sidecar
  read_aloud_tts/ FastAPI server + engine adapters
  voices/         Chatterbox reference clips
  pyproject.toml  uv-managed dependencies

scripts/          install-sidecar.sh, reinstall.sh, launchd template
```

## Status

v0.1 — Swift skeleton + Apple voices working, sidecar wiring stubbed.

Tracking the build phases from the implementation plan:

- [x] v0.1 — Skeleton + Apple voices
- [ ] v0.2 — Sidecar plumbing (install script + healthcheck UI)
- [ ] v0.3 — Kokoro streaming for English
- [ ] v0.4 — Chatterbox streaming for Polish
- [ ] v0.5 — Per-app overrides, pronunciation dictionary

## License

MIT — see [LICENSE](LICENSE).
