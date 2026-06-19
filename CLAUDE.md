# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
make build      # Release build + assemble .app + ad-hoc codesign
make run        # Build and launch the app
make install    # Build and copy to /Applications/
make clean      # Remove build artifacts
swift build     # Debug build only (no .app assembly)

# Signed distribution build:
make build SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

No external dependencies — system frameworks only (AppKit, SwiftUI, AVFoundation, Speech, CoreGraphics, Carbon).

## Architecture

**macOS menu-bar app** (LSUIElement — no Dock icon). Hold Fn key to record speech, release to inject transcribed text into the focused input field. Built as a single Swift Package Manager executable target (`Package.swift`), minimum macOS 14.

### Component wiring (top-down)

```
main.swift → AppDelegate → RecordingCoordinator
                                ├── GlobalEventMonitor (CGEvent tap, Fn key)
                                ├── AudioCaptureManager (AVAudioEngine, RMS + speech buffer)
                                ├── SpeechRecognizer (SFSpeechRecognizer streaming)
                                ├── CapsuleController (NSPanel + NSHostingView)
                                ├── TextInjector (clipboard save/restore, Cmd+V via CGEvent)
                                └── LLMRefiner (OpenAI-compatible API, non-streaming)
```

- **AppKit** owns the shell: NSStatusBar, CGEvent tap, NSPanel capsule, clipboard injection.
- **SwiftUI** owns interior content: waveform animation, transcription label, settings form — all hosted via `NSHostingView`.

### State machine

```
Idle →(Fn held ≥200ms)→ Recording →(Fn released)→ [Refining] → Injecting → Dismissing → Idle
```

- Fn re-presses during Recording/Refining are ignored (guard: `isRecording`).
- If Fn released before 200ms debounce, timer cancelled — no recording starts.
- If no speech detected during recording (RMS never > 0.01), flash warning, no injection.
- LLM refinement is skipped unless both `llmEnabled` AND credentials are configured.

### Audio pipeline

Single `AVAudioEngine` with a tap on input node (bus 0, buffer size 1024). The same tap callback fans out to both RMS computation and `SFSpeechAudioBufferRecognitionRequest.append(buffer)`. No separate audio session.

### CGEvent tap — Fn key handling

- Key code 63 (Fn). Solo hold: intercept and suppress (return `nil`).
- Fn + any other key: cancel recording timer, pass through — preserves Fn-as-modifier (e.g., Fn+Delete).
- Only 200ms+ holds trigger recording (debounce via `DispatchWorkItem`).
- Accessibility permission required (`CGPreflightListenEventTap`). Checked at launch.

### Text injection

Clipboard-based with CJK input source awareness:
1. Save clipboard + detect current input source
2. If CJK (zh/ja/ko prefix): switch to ABC keyboard, then post Cmd+V via CGEvent
3. After 200ms: restore original input source, then restore clipboard

### LLM refinement

OpenAI-compatible chat completions. Non-streaming, temperature 0, 5-second timeout. Hardcoded conservative system prompt that only fixes homophones, English technical terms misrecognized as Chinese, and number/date formatting. On API error: falls back to raw transcription + flashes menu bar amber.

### Thread safety

- Audio tap callback runs on real-time thread — computes RMS + appends buffer there, dispatches to main for UI.
- Speech recognition callback runs on arbitrary serial queue — dispatches to main for state updates.
- Streaming UI updates use `withObservationTracking` + `onChange` re-registration loop (not timer-based).
- No locks. All shared state is single-consumer (main thread for UI). RMS Float is stale-read tolerant.

## UserDefaults keys

| Key | Default | Purpose |
|-----|---------|---------|
| `recognitionLocale` | `zh-CN` | Speech recognition locale |
| `llmEnabled` | `false` | LLM refinement toggle |
| `llmBaseURL` | `https://api.deepseek.com/v1` | API base URL |
| `llmApiKey` | `""` | API key |
| `llmModel` | `deepseek-v4-flash` | Model name |

## Info.plist

Fixed `CFBundleIdentifier` (`com.voiceinput.app`) — must not change, as it ties to TCC permission grants. `LSUIElement=true` for menu-bar-only mode.
