# Voice Input

A macOS menu-bar voice dictation app that transcribes speech to text with a single keypress.
Hold the **Fn key** to record, release to inject transcribed text into any focused input field.

Built with Swift, AppKit + SwiftUI, using Apple's on-device Speech Recognition framework.

## Features

- **Hold & Speak** — Hold Fn to record, release to paste. No clicking, no switching apps.
- **Streaming Transcription** — Real-time text appears as you speak via `SFSpeechRecognizer`.
- **Waveform Feedback** — Elegant floating capsule with RMS-driven 5-bar audio visualization.
- **CJK Input Method Aware** — Automatically detects Chinese/Japanese/Korean input sources and temporarily switches to ABC keyboard before pasting, preventing input method interception.
- **Multi-Language** — Simplified Chinese (default), Traditional Chinese, English, Japanese, Korean.
- **LLM Refinement** — Optional post-processing via OpenAI-compatible API to fix speech recognition errors (Chinese homophones, English technical terms like 配森→Python).
- **Menu Bar Only** — `LSUIElement` mode. No Dock icon, minimal footprint.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for building)
- Microphone permission
- Accessibility permission (for global Fn key monitoring)

## Quick Start

### Install via Homebrew (coming soon)

```bash
brew install --cask voice-input
```

### Manual Install

Download the latest `.app` from [Releases](https://github.com/1998x-stack/voice-input/releases), move to `/Applications/`, and run.

### Build from Source

```bash
git clone https://github.com/1998x-stack/voice-input.git
cd voice-input
make build
make install
```

## Usage

1. **Grant Permissions** — On first launch, the app will prompt for:
   - **Microphone** (System Settings → Privacy & Security → Microphone)
   - **Accessibility** (System Settings → Privacy & Security → Accessibility) — required for Fn key monitoring

2. **Select Language** — Click the menu bar icon (🎤) → Language → choose your speech language

3. **Record** — Hold the **Fn key** for >200ms, speak into your microphone
   - A capsule appears at the bottom of the screen showing the waveform and live transcription

4. **Release** — Let go of Fn. The transcribed text is pasted into the focused input field.

5. **LLM Refinement** (optional) — Configure in Settings:
   - Enter your API credentials (OpenAI-compatible, e.g., DeepSeek)
   - Enable "LLM Refinement" in the menu
   - After recording, the capsule shows "Refining..." while the API corrects recognition errors

### Language Support

| Language | Locale | Recognition |
|---|---|---|
| 简体中文 | zh-CN | On-device |
| English | en-US | On-device |
| 繁體中文 | zh-TW | On-device |
| 日本語 | ja-JP | On-device |
| 한국어 | ko-KR | On-device (macOS 14+) |

All languages use Apple's on-device recognition — no network required for transcription.

## Architecture

```
Sources/VoiceInput/
├── main.swift                  — Entry point
├── AppDelegate.swift           — Status bar, menu, permissions, settings window
├── GlobalEventMonitor.swift    — CGEvent tap for Fn key
├── AudioCaptureManager.swift   — AVAudioEngine with dual-consumer tap (RMS + Speech)
├── SpeechRecognizer.swift      — SFSpeechRecognizer streaming
├── RecordingCoordinator.swift  — State machine orchestration
├── CapsuleController.swift     — NSPanel + NSVisualEffectView capsule
├── CapsuleContentView.swift    — SwiftUI waveform + transcription label
├── TextInjector.swift          — Clipboard + CJK input source handling
├── LLMRefiner.swift            — OpenAI-compatible API client
└── SettingsWindowView.swift    — SwiftUI settings form
```

## LLM Refinement

The app integrates an OpenAI-compatible chat completions endpoint to correct speech recognition errors.

### System Prompt Philosophy

The refinement is **extremely conservative** — it only fixes:

- Chinese homophone errors (words that sound the same but are written differently)
- English technical terms incorrectly converted to Chinese (配森→Python, 杰森→JSON)
- Obvious number/date formatting errors

It will **not** rewrite, polish, or change correct content. If the input looks correct, it returns it unchanged.

### Configuration

| Setting | Default | Description |
|---|---|---|
| API Base URL | `https://api.deepseek.com/v1` | Must include `/v1` path |
| API Key | (empty) | Your API key |
| Model | `deepseek-v4-flash` | Any compatible model |

## Makefile Targets

| Target | Command |
|---|---|
| `build` | Compile release build, assemble `.app` bundle, ad-hoc codesign |
| `run` | Build and launch the app |
| `install` | Copy `.app` to `/Applications/` |
| `clean` | Remove build artifacts |

### Signing

Default: ad-hoc codesign. For distribution:

```bash
make build SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

## Permissions

Voice Input requires two macOS permissions:

| Permission | Why | Where |
|---|---|---|
| **Microphone** | Capture audio for speech recognition | System Settings → Privacy & Security → Microphone |
| **Accessibility** | Monitor Fn key globally via CGEvent tap | System Settings → Privacy & Security → Accessibility |

The app will guide you on first launch if permissions are missing.

## Troubleshooting

### "Speech recognition is not available"
- Ensure you're connected to the internet on first use (required for on-device model download)
- Check mic permission in System Settings

### "Accessibility Permission Required"
- Add Voice Input in System Settings → Privacy & Security → Accessibility
- If already listed, remove and re-add

### Fn key opens emoji picker instead of recording
- Ensure Accessibility permission is granted
- On some Macs, the Globe key may need to be configured: System Settings → Keyboard → Press fn/globe key to → "Do Nothing"

### Text pastes incorrectly (Chinese input method)
- This is handled automatically — the app switches to ABC keyboard before pasting
- If issues persist, ensure Voice Input has Accessibility permission

## License

MIT
