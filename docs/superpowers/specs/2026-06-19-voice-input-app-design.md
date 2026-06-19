# Voice Input App — Design Spec

**Date:** 2026-06-19
**Platform:** macOS 14+
**Language:** Swift 5.9
**Build:** Swift Package Manager

## Overview

A macOS menu-bar voice dictation app. Hold Fn to record speech, release to inject transcribed text into the focused input field. Defaults to Simplified Chinese (zh-CN) recognition with optional LLM refinement for mixed Chinese-English speech.

---

## Architecture

Hybrid AppKit + SwiftUI, single executable target.

- **AppKit** owns the shell: NSApplication (LSUIElement), NSStatusBar, CGEvent tap, NSPanel capsule, clipboard injection.
- **SwiftUI** owns the interior content: waveform animation, transcription label, settings form. Hosted via NSHostingView.

### Component Map (11 files)

```
Sources/VoiceInput/
  main.swift                  — Entry point, NSApplication setup
  AppDelegate.swift           — Status bar, menu, permission check, settings window, owns RecordingCoordinator
  GlobalEventMonitor.swift    — CGEvent tap for Fn key: solo hold → intercept, Fn+combo → pass through. 200ms debounce.
  AudioCaptureManager.swift   — Single AVAudioEngine, installs tap on input node, fans out buffer to RMS and speech recognizer
  SpeechRecognizer.swift      — SFSpeechRecognizer streaming, locale from UserDefaults, eager init at launch for download priming
  RecordingCoordinator.swift  — Orchestrator: wires Fn → Audio → Speech → Capsule → LLM → Inject. cancel() for cleanup.
  CapsuleController.swift     — NSPanel lifecycle, NSHostingView bridge, elastic width via intrinsicContentSize, entry/exit animations
  CapsuleContentView.swift    — SwiftUI: 5-bar waveform (TimelineView 30fps, envelope-smoothed RMS) + elastic transcription label + Refining spinner
  TextInjector.swift          — Clipboard save/restore, CJK input source detection/switch with poll confirmation, Cmd+V via CGEvent, 200ms post-paste restore
  LLMRefiner.swift            — OpenAI-compatible API client, non-streaming, temperature 0, 5s timeout, conservative system prompt
  SettingsWindowView.swift    — SwiftUI: API Base URL, API Key (SecureField), Model, Test + Save buttons

  Info.plist                  — 7 keys: CFBundleIdentifier, CFBundleName, CFBundleExecutable, LSUIElement, NSMicrophoneUsageDescription, version keys
```

### Dependencies

System frameworks only: AppKit, SwiftUI, AVFoundation, Speech. LLMRefiner uses URLSession — no external packages. No entitlements file needed (ad-hoc signing; Accessibility permission is a TCC grant, not a provisioning entitlement).

---

## State Machine

```
Idle →(Fn held ≥200ms)→ Recording →(Fn released)→ [Refining] → Injecting → Dismissing → Idle
```

| State | Behavior |
|---|---|
| **Idle** | Event tap active. Menu bar icon: `mic.fill`, default tint. |
| **Recording** | Capsule appears (spring 0.35s). Mic active, speech recognition streaming. Waveform RMS-driven, text updates live. Menu bar icon: blue tint. |
| **Refining** | (Only if LLM enabled+configured) Capsule shows spinner + "Refining..." text. Non-streaming POST to API. On error/timeout: fallback to raw text + flash menu bar amber. |
| **Injecting** | Save clipboard → if CJK detected, switch to ABC (poll confirm ≤100ms) → Cmd+V → wait 200ms → restore input source → restore clipboard. |
| **Dismissing** | Capsule scale-out animation (0.22s). Menu bar icon back to default tint. |

### State Guards
- Only Idle → Recording transition is valid. Fn re-presses during Recording/Refining/Injecting are ignored.
- Recording duration < 200ms: discarded (no injection).
- No speech captured: flash menu bar warning, no injection.

---

## CGEvent Tap — Fn Key

- **Solo Fn hold:** Intercept + suppress event (return NULL). Triggers recording.
- **Fn + any other key:** Pass through unmodified. Preserves system modifier behavior (Fn+Delete = forward delete, etc.).
- **200ms debounce:** on Fn keyDown, schedule a timer. If keyUp arrives before 200ms, cancel → accidental tap.
- **Accessibility permission:** Check `CGPreflightListenEventTap` at launch. If denied, guide user to System Settings → Privacy & Security → Accessibility.

---

## Audio Pipeline

Single `AVAudioEngine` with a tap on the input node (bus 0, buffer size 1024). The tap callback:

1. Compute RMS from `AVAudioPCMBuffer.floatChannelData` (simple sum of squares)
2. `DispatchQueue.main.async` → publish RMS to `@Observable` property for waveform
3. `recognitionRequest.append(buffer)` — thread-safe per SFSpeechRecognizer docs

No locks needed — RMS is a single Float. No separate audio session for speech recognition.

RMS formula:
```
rms = sqrt(sum(sample^2) / frameLength)
```

---

## Capsule Window

- **Type:** NSPanel, `.nonactivatingPanel` + `.hudWindow` material via NSVisualEffectView
- **Frame:** Centered at bottom of screen containing mouse cursor. Height 56px, corner radius 28px. No traffic lights, no titlebar.
- **Width:** Elastic 260–660px. Driven by `NSHostingView.intrinsicContentSize` observation. Animated via `NSAnimationContext` (0.25s).
- **Level:** `.floating`
- **Collection behavior:** `.canJoinAllSpaces`, `.transient`, `.fullScreenAuxiliary`

### Waveform (44×32px)
- 5 vertical bars: 3.5px wide, 3px gap, corner radius 2px
- RMS-driven via `TimelineView(.animation(minimumInterval: 1/30))` at ~30fps
- Bar weights: [0.5, 0.8, 1.0, 0.75, 0.55] — center-high, sides-low
- Envelope follower: attack 0.40, release 0.15 per frame
- Per-bar jitter: ±4% random (uniform distribution)
- Bar height clamped to 3–32px
- Gradient fill: #007AFF → #5AC8FA
- Envelope math: `envelope = envelope * (1 - coeff) + target * coeff` where coeff = attack if target > envelope else release

### Transcription Label
- Elastic width: 160–560px, single line, system font 15pt, white
- When empty/minimal: shows subtle placeholder
- During Refining: shows ProgressView spinner + "Refining..." text

### Animations
- Entry: spring animation, 0.35s (scale 0.8→1.0 + opacity 0→1)
- Text width change: `NSAnimationContext` duration 0.25s
- Exit: scale 1.0→0.9 + opacity 1→0, 0.22s

---

## Menu Bar

- **Icon:** SF Symbol `mic.fill`
- **Icon states:**
  - Idle: default tint
  - Recording: `.contentTintColor = .systemBlue`
  - Warning flash: `.contentTintColor = .systemOrange` for 1500ms, then back to default
  - Mic denied persistent: `mic.slash.fill` + `.systemOrange`

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

- Language stored as locale identifier in UserDefaults (`recognitionLocale`, default: `zh-CN`)
- Language change takes effect on next recording (does not interrupt active)
- LLM toggle stored in UserDefaults (`llmEnabled`, default: `false`)

### Locale Mapping

| Menu Label | UserDefaults Value | On-Device Support |
|---|---|---|
| English | `en-US` | Yes |
| 简体中文 | `zh-CN` | Yes |
| 繁體中文 | `zh-TW` | Yes |
| 日本語 | `ja-JP` | Yes |
| 한국어 | `ko-KR` | Yes (macOS 14+) |

---

## Text Injection

1. Save clipboard (`NSPasteboard.general.string`)
2. Detect input source via `TISCopyCurrentKeyboardInputSource`
3. If CJK (zh, ja, ko): call `TISSelectInputSource(ABC)`, poll `TISCopyCurrentKeyboardInputSource` until switch confirms (timeout 100ms)
4. Clear clipboard, set to transcribed/refined text
5. Post Cmd+V via CGEvent (keyDown + keyUp, keyCode 0x09, cmd flag)
6. `DispatchQueue.main.asyncAfter(200ms)`:
   - If was CJK: restore original input source via `TISSelectInputSource`
   - Clear clipboard, restore original content

---

## LLM Refinement

### API
- Endpoint: `{baseURL}/chat/completions` (trailing slash stripped from base URL)
- Method: POST, non-streaming
- Payload: `{ model, messages: [{system}, {user}], temperature: 0, max_tokens: 2048 }`
- Timeout: 5 seconds, no retries
- Config keys in UserDefaults: `llmBaseURL`, `llmApiKey`, `llmModel`

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
- Single-instance NSWindow (.titled + .closable, not resizable), ~380px wide
- `isReleasedWhenClosed = false` — re-clicking Settings brings existing window forward
- Fields: API Base URL (TextField), API Key (SecureField), Model (TextField)
- API Key can be fully cleared
- Test button: sends `{ model, messages: [{role: "user", content: "Hello"}], max_tokens: 10 }` → shows success (any content) or error (message in alert)
- Save button: persists all fields to UserDefaults
- Pre-populated from current UserDefaults

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Mic permission not granted | Check on launch. Denied: icon = `mic.slash.fill` + orange. Fn press: flash warning. |
| Fn hold < 200ms | Timer cancelled, ignored. |
| No speech captured | Flash menu bar orange warning 1.5s, no injection. |
| Speech recognizer unavailable | Capsule shows "Unavailable", no injection. Recognizer created eagerly at launch to trigger on-device download. |
| on-device locale not downloaded | `SFSpeechRecognizer(locale:)` returns nil → menu shows disabled indicator. Auto-downloads when used with network. |
| LLM API error / timeout (5s) | Fall back to raw transcription, inject it, flash menu bar amber 1.5s. |
| Clipboard restore failure | Best-effort — text already injected. |
| Cmd+V lands nowhere | Text lost. Flash menu bar orange warning. Clipboard restored. |
| App terminated mid-recording | `applicationWillTerminate` → `coordinator.cancel()` → stop audio, cancel speech task, dismiss panel. `GlobalEventMonitor.deinit` invalidates CFMachPort. |
| Accessibility permission missing | `CGPreflightListenEventTap` fails at launch → dialog guiding user to System Settings. Icon shows warning until granted. |

---

## Thread Safety

- Audio tap callback: real-time thread. Compute RMS + append buffer here, dispatch UI update to main.
- Speech recognition result callback: arbitrary serial queue. Dispatch transcription update to main.
- No locks. All shared state is single-consumer (main thread for UI, audio thread for capture).
- RMS: Float (atomic on 64-bit), stale read is acceptable for visual display.

---

## Build & Packaging

### Package.swift
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "VoiceInput", path: "Sources/VoiceInput")
    ]
)
```

### Makefile

| Target | Command |
|---|---|
| `build` | `swift build -c release --product VoiceInput`, then assemble `.app` bundle structure, copy binary + Info.plist, ad-hoc codesign with `--deep --force` |
| `run` | `open .build/release/VoiceInput.app` |
| `install` | `cp -r .build/release/VoiceInput.app /Applications/` |
| `clean` | `swift package clean` |

### .app Bundle Structure
```
VoiceInput.app/
├── Contents/
│   ├── MacOS/
│   │   └── VoiceInput       (built binary)
│   ├── Info.plist
│   └── PkgInfo              ("APPL????")
```

### Signing
- Default: `codesign -s - --deep --force` (ad-hoc)
- `SIGNING_IDENTITY` Makefile variable for Developer ID distribution
- No entitlements file for ad-hoc builds
- Fixed `CFBundleIdentifier` in Info.plist so TCC permission grants survive rebuilds

### Info.plist Keys

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `com.voiceinput.app` |
| `CFBundleName` | `Voice Input` |
| `CFBundleExecutable` | `VoiceInput` |
| `LSUIElement` | `true` |
| `NSMicrophoneUsageDescription` | "Voice Input needs microphone access to transcribe your speech." |
| `CFBundleVersion` | `1` |
| `CFBundleShortVersionString` | `1.0.0` |

---

## Default Configuration

| UserDefaults Key | Default | Description |
|---|---|---|
| `recognitionLocale` | `zh-CN` | Speech recognition locale identifier |
| `llmEnabled` | `false` | LLM refinement toggle |
| `llmBaseURL` | `https://api.deepseek.com/v1` | API base URL (include version path) |
| `llmApiKey` | `""` (empty) | API key |
| `llmModel` | `deepseek-v4-flash` | Model name |
