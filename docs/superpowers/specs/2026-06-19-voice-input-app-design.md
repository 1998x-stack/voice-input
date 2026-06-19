# Voice Input App — Design Spec

**Date:** 2026-06-19
**Platform:** macOS 14+
**Language:** Swift
**Build:** Swift Package Manager

## Overview

A macOS menu-bar voice dictation app. Hold Fn to record speech, release to inject transcribed text into the focused input field. Defaults to Simplified Chinese (zh-CN) recognition with optional LLM refinement for mixed Chinese-English speech.

---

## Architecture

Hybrid AppKit + SwiftUI, single executable target.

- **AppKit** owns the shell: NSApplication (LSUIElement), NSStatusBar, CGEvent tap, NSPanel capsule, clipboard injection.
- **SwiftUI** owns the interior content: waveform animation, transcription label, settings form. Hosted via NSHostingView.

### Component Map (10 files)

```
Sources/VoiceInput/
  main.swift                  — Entry point, NSApplication setup
  AppDelegate.swift           — Status bar, menu, permission check, owns RecordingCoordinator
  GlobalEventMonitor.swift    — CGEvent tap for Fn key (press/release callbacks, 200ms debounce, suppresses Fn event)
  AudioCaptureManager.swift   — AVCaptureSession, provides RMS level stream (~50ms intervals)
  SpeechRecognizer.swift      — SFSpeechRecognizer streaming, language from UserDefaults
  RecordingCoordinator.swift  — Orchestrator: wires Fn → Audio → Speech → Capsule → LLM → Inject
  CapsuleController.swift     — NSPanel lifecycle, NSHostingView bridge, entry/exit animations
  CapsuleContentView.swift    — SwiftUI: 5-bar waveform + elastic transcription label + Refining state
  TextInjector.swift          — Clipboard save/restore, CJK input source detection/switch, Cmd+V via CGEvent
  LLMRefiner.swift            — OpenAI-compatible API client, 5s timeout, conservative system prompt
  SettingsWindow.swift        — SwiftUI: API Base URL, API Key (SecureField), Model, Test + Save buttons

  Info.plist                  — LSUIElement = YES, NSMicrophoneUsageDescription
  VoiceInput.entitlements     — com.apple.security.automation.apple-events (for CGEvent tap)
```

### Dependencies

All components depend only on system frameworks (AppKit, SwiftUI, AVFoundation, Speech). The LLMRefiner uses URLSession directly — no external packages.

---

## State Machine

```
Idle →(Fn held ≥200ms)→ Recording →(Fn released)→ [Refining] → Injecting → Dismissing → Idle
```

| State | Behavior |
|---|---|
| **Idle** | Event tap active. Menu bar icon visible, normal appearance. |
| **Recording** | Capsule appears (spring 0.35s). Mic active, speech recognition streaming. Waveform RMS-driven, text updates live. |
| **Refining** | (Only if LLM enabled+configured) Capsule shows spinner + "Refining..." text. Sends transcription to API. On error/timeout: fallback to raw text + flash menu bar amber. |
| **Injecting** | Save clipboard → switch to ASCII input source if CJK detected → Cmd+V → restore input source → restore clipboard. |
| **Dismissing** | Capsule scale-out animation (0.22s). Return to Idle. |

### State Guards
- Only Idle → Recording transition is valid. Rapid Fn re-presses during Recording/Refining/Injecting are ignored.
- Recording duration under 200ms is discarded (no injection).
- If no speech detected: flash menu bar warning, no injection, return to Idle.

---

## Capsule Window

- **Type:** NSPanel, `.nonactivatingPanel` (doesn't activate the app), `.hudWindow` material via NSVisualEffectView
- **Frame:** Centered at bottom of main screen. Height 56px, corner radius 28px, no traffic lights, no titlebar
- **Width:** Elastic 260–660px (waveform 44px + gap 16px + text 160–560px + horizontal padding 40px)
- **Level:** `.floating`, `collectionBehavior = .canJoinAllSpaces`
- **Content (L→R):**

### Waveform (44×32px)
- 5 vertical bars driven by real-time audio RMS levels
- Bar weights: [0.5, 0.8, 1.0, 0.75, 0.55] — center-high, sides-low
- Envelope smoothing: attack 40% (fast rise), release 15% (gradual decay)
- ±4% random jitter per bar per frame for organic feel
- Bars use gradient fill: #007AFF → #5AC8FA, corner radius 2px, width 3.5px each, gap 3px

### Transcription Label
- Elastic width: 160–560px (text clips if needed)
- Font: system, 15pt, white, single line
- Width transitions animated (0.25s)
- During Refining: shows spinner + "Refining..."

### Animations
- Entry: spring animation, 0.35s (scale + fade)
- Text width change: smooth 0.25s transition
- Exit: scale-out + fade, 0.22s

---

## Menu Bar

- **Icon:** SF Symbol `mic.fill`
- **Menu structure:**

```
Language ▸
  English
  ✓ 简体中文
  繁體中文
  日本語
  한국어
──────────
LLM Refinement ▸
  ✓ Enabled
  Settings...
──────────
Quit
```

- Language selection persisted in UserDefaults (`recognitionLanguage` key, default: `zh-CN`)
- Language change takes effect on the next recording session (does not interrupt an active recording)
- LLM toggle persisted in UserDefaults (`llmEnabled` key, default: `false`)

---

## Text Injection

1. Save current clipboard content
2. Detect current input source via `TISCopyCurrentKeyboardInputSource`
3. If input source is CJK (zh, ja, ko): switch to ASCII (ABC/US keyboard) via `TISSelectInputSource`
4. Set clipboard to transcribed/refined text
5. Post Cmd+V via CGEvent (`CGEvent(keyboardEvent: virtualKey: 0x09, keyDown: true)`)
6. Small delay (50ms) for paste to land
7. Restore original input source if it was switched
8. Restore original clipboard content

---

## LLM Refinement

### API
- OpenAI-compatible chat completions endpoint
- Config: `llmBaseURL`, `llmApiKey`, `llmModel` in UserDefaults
- Timeout: 5 seconds
- No retries on failure

### System Prompt (hardcoded)

```
You are a conservative speech recognition post-processor. Your task is to fix ONLY obvious recognition errors in the user's dictated text. Specifically:

1. Fix Chinese homophone errors (words that sound the same but are written differently)
2. Restore English technical terms that were incorrectly converted to Chinese (e.g. 配森→Python, 杰森→JSON, 加瓦→Java)
3. Fix obvious number/date formatting errors common in speech recognition

DO NOT:
- Rewrite, polish, or improve the text's style
- Add, remove, or change any content that appears correct
- Fix grammar unless it's clearly a recognition error
- Add punctuation unless the original clearly intended it

If the input looks correct, return it exactly as-is with no changes.

Respond with ONLY the corrected text. No explanations, no prefixes, no markdown.
```

### Settings Window
- SwiftUI window, ~380px wide
- Fields: API Base URL (TextField), API Key (SecureField with clearable toggle), Model (TextField)
- Test button: sends "Hello" → validates response is non-empty → shows success/failure alert
- Save button: persists to UserDefaults
- All fields pre-populated from current UserDefaults values

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Mic permission not granted | Check on launch. Denied: menu bar icon shows warning. Fn press: flash warning, no recording. |
| Fn hold < 200ms | Ignored — accidental tap. |
| No speech captured | Flash menu bar warning, no injection. |
| Speech recognizer unavailable | Capsule shows "Unavailable", no injection on release. |
| LLM API error / timeout (5s) | Fall back to raw transcription, inject it, flash menu bar amber. |
| Clipboard restore failure | Best-effort. Text already injected at this point. |
| Cmd+V lands nowhere | Text lost. Flash menu bar warning. Clipboard restored. |
| App terminated mid-recording | Cleanup in `applicationWillTerminate`: stop audio, remove event tap. |

---

## Build & Packaging

### Package.swift
Single product: `VoiceInput` (executable).
Platforms: macOS `.v14`.

### Makefile

| Target | Command |
|---|---|
| `build` | `swift build -c release --product VoiceInput` |
| `run` | `swift run -c release` |
| `install` | Copy `.build/release/VoiceInput.app` to `/Applications/` |
| `clean` | `swift package clean` |

### Signing
Default: ad-hoc codesign (`codesign -s -`). Variable `SIGNING_IDENTITY` for Developer ID distribution.
Entitlements embedded: `com.apple.security.automation.apple-events`.

### App Bundle
LSUIElement = YES. No Dock icon, menu bar only.
NSMicrophoneUsageDescription must be present for mic permission dialog.

---

## Default Configuration

| Key | Default | Description |
|---|---|---|
| `recognitionLanguage` | `zh-CN` | Speech recognition locale |
| `llmEnabled` | `false` | LLM refinement toggle |
| `llmBaseURL` | `https://api.deepseek.com/v1` | API endpoint |
| `llmApiKey` | `""` (empty) | API key |
| `llmModel` | `deepseek-v4-flash` | Model name |
