# Voice Input App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar voice dictation app with streaming speech recognition, Fn-key trigger, waveform capsule UI, and optional LLM refinement.

**Architecture:** Hybrid AppKit + SwiftUI, single executable target. AppKit owns the shell (NSStatusBar, CGEvent tap, NSPanel, clipboard injection). SwiftUI owns interior content (waveform, transcription label, settings form). Single AVAudioEngine fans audio to both RMS computation and SFSpeechRecognizer. No external packages.

**Tech Stack:** Swift 5.9, macOS 14+, AppKit, SwiftUI, AVFoundation, Speech

---

### Task 1: Project Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Sources/VoiceInput/Info.plist`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            path: "Sources/VoiceInput"
        )
    ]
)
```

- [ ] **Step 2: Verify Package.swift parses**

Run: `swift package describe`
Expected: prints package info, no errors.

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.voiceinput.app</string>
    <key>CFBundleName</key>
    <string>Voice Input</string>
    <key>CFBundleExecutable</key>
    <string>VoiceInput</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice Input needs microphone access to transcribe your speech.</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
</dict>
</plist>
```

- [ ] **Step 4: Create Makefile**

```makefile
APP_NAME = VoiceInput
BINARY = .build/release/$(APP_NAME)
APP_BUNDLE = .build/release/$(APP_NAME).app
PLIST = Sources/$(APP_NAME)/Info.plist
SIGNING_IDENTITY ?= -

.PHONY: build run install clean

build:
    swift build -c release --product $(APP_NAME)
    mkdir -p $(APP_BUNDLE)/Contents/MacOS
    cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/
    cp $(PLIST) $(APP_BUNDLE)/Contents/
    echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
    codesign -s $(SIGNING_IDENTITY) --deep --force $(APP_BUNDLE)

run: build
    open $(APP_BUNDLE)

install: build
    cp -r $(APP_BUNDLE) /Applications/

clean:
    swift package clean
    rm -rf $(APP_BUNDLE)
```

- [ ] **Step 5: Verify Makefile**

Run: `make clean`
Expected: cleans without error.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Makefile Sources/VoiceInput/Info.plist
git commit -m "chore: add project skeleton — Package.swift, Makefile, Info.plist"
```

---

### Task 2: Entry Point

**Files:**
- Create: `Sources/VoiceInput/main.swift`

- [ ] **Step 1: Create main.swift**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
```

- [ ] **Step 2: Create minimal AppDelegate stub**

Create `Sources/VoiceInput/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Will be filled in later tasks
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build`
Expected: builds successfully. The app won't do anything useful yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceInput/main.swift Sources/VoiceInput/AppDelegate.swift
git commit -m "feat: add entry point and AppDelegate stub"
```

---

### Task 3: AudioCaptureManager

**Files:**
- Create: `Sources/VoiceInput/AudioCaptureManager.swift`

- [ ] **Step 1: Create AudioCaptureManager.swift**

```swift
import AVFoundation
import Foundation
import Observation

@Observable
final class AudioCaptureManager {
    var rmsLevel: Float = 0
    var isRunning: Bool = false

    private let engine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let analysisQueue = DispatchQueue(label: "com.voiceinput.audio", qos: .userInteractive)

    func setRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        recognitionRequest = request
    }

    func start() throws {
        guard !engine.isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let rms = Self.computeRMS(buffer)
            DispatchQueue.main.async {
                self.rmsLevel = rms
            }
            self.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        DispatchQueue.main.async {
            self.rmsLevel = 0
        }
    }

    static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(frameLength))
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/AudioCaptureManager.swift
git commit -m "feat: add AudioCaptureManager with single-engine audio tap and RMS computation"
```

---

### Task 4: SpeechRecognizer

**Files:**
- Create: `Sources/VoiceInput/SpeechRecognizer.swift`

- [ ] **Step 1: Create SpeechRecognizer.swift**

```swift
import Speech
import Foundation
import Observation

@Observable
final class SpeechRecognizer {
    var partialText: String = ""
    var finalText: String = ""
    var isAvailable: Bool = false
    var localeIdentifier: String

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechTask?
    private let request = SFSpeechAudioBufferRecognitionRequest()

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
        refreshRecognizer()
    }

    func setLocale(_ identifier: String) {
        guard identifier != localeIdentifier else { return }
        localeIdentifier = identifier
        refreshRecognizer()
    }

    private func refreshRecognizer() {
        let locale = Locale(identifier: localeIdentifier)
        recognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = recognizer?.isAvailable ?? false
    }

    func audioBufferRequest() -> SFSpeechAudioBufferRecognitionRequest {
        request.shouldReportPartialResults = true
        return request
    }

    func startRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw RecognitionError.unavailable
        }

        partialText = ""
        finalText = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalText = result.bestTranscription.formattedString
                    }
                }
                if let error {
                    self.partialText = ""
                }
            }
        }
    }

    func stopRecognition() {
        recognitionTask?.finish()
        recognitionTask = nil
    }

    enum RecognitionError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "Speech recognition is not available. Check network or locale support."
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/SpeechRecognizer.swift
git commit -m "feat: add SpeechRecognizer with streaming SFSpeechRecognizer and locale switching"
```

---

### Task 5: GlobalEventMonitor

**Files:**
- Create: `Sources/VoiceInput/GlobalEventMonitor.swift`

- [ ] **Step 1: Create GlobalEventMonitor.swift**

```swift
import CoreGraphics
import Foundation

final class GlobalEventMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressTimer: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.2
    private var isPressed = false

    func checkAccessibilityPermission() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        return CGPreflightListenEventTap(.cgSessionEventTap, .headInsertEventTap)
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<GlobalEventMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    func stop() {
        pressTimer?.cancel()
        pressTimer = nil
        isPressed = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
        }
    }

    deinit {
        stop()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == 63 {
            switch type {
            case .keyDown:
                return handleFnKeyDown(event: event)
            case .keyUp:
                return handleFnKeyUp(event: event)
            default:
                return Unmanaged.passUnretained(event)
            }
        } else if isPressed && pressTimer != nil {
            // Another key pressed while Fn is held — Fn is being used as modifier.
            // Cancel the recording timer and let all subsequent events through.
            pressTimer?.cancel()
            pressTimer = nil
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFnKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !isPressed else { return Unmanaged.passUnretained(event) }
        isPressed = true

        let timer = DispatchWorkItem { [weak self] in
            self?.onPress?()
        }
        pressTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: timer)

        return nil
    }

    private func handleFnKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isPressed else { return Unmanaged.passUnretained(event) }
        isPressed = false

        if let timer = pressTimer {
            timer.cancel()
            pressTimer = nil
            onRelease?()
        } else {
            onRelease?()
        }

        return nil
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/GlobalEventMonitor.swift
git commit -m "feat: add GlobalEventMonitor with Fn key detection and 200ms debounce"
```

---

### Task 6: TextInjector

**Files:**
- Create: `Sources/VoiceInput/TextInjector.swift`

- [ ] **Step 1: Create TextInjector.swift**

```swift
import AppKit
import Carbon
import CoreGraphics

final class TextInjector {
    func inject(text: String) {
        guard !text.isEmpty else { return }

        let originalClipboard = NSPasteboard.general.string(forType: .string)
        let originalInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let isCJK = inputSourceIsCJK(originalInputSource)

        if isCJK {
            selectABCInputSource()
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        postCmdV()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [originalClipboard, originalInputSource, isCJK] in
            if isCJK, let source = originalInputSource {
                TISSelectInputSource(source)
            }
            NSPasteboard.general.clearContents()
            if let clip = originalClipboard {
                NSPasteboard.general.setString(clip, forType: .string)
            }
        }
    }

    private func inputSourceIsCJK(_ source: TISInputSource?) -> Bool {
        guard let source else { return false }
        guard let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return false }
        let langArray = Unmanaged<CFArray>.fromOpaque(languages).takeUnretainedValue() as [AnyObject]
        let cjkPrefixes = ["zh", "ja", "ko"]
        for lang in langArray {
            if let langStr = lang as? String {
                for prefix in cjkPrefixes {
                    if langStr.hasPrefix(prefix) { return true }
                }
            }
        }
        return false
    }

    private func selectABCInputSource() {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        for source in sources {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String? else { continue }
            if id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US" {
                TISSelectInputSource(source)
                return
            }
        }
    }

    private func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/TextInjector.swift
git commit -m "feat: add TextInjector with CJK input source detection, clipboard save/restore, and Cmd+V paste"
```

---

### Task 7: LLMRefiner

**Files:**
- Create: `Sources/VoiceInput/LLMRefiner.swift`

- [ ] **Step 1: Create LLMRefiner.swift**

```swift
import Foundation

final class LLMRefiner {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    private let systemPrompt = """
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
    """

    struct Config {
        let baseURL: String
        let apiKey: String
        let model: String
    }

    func refine(text: String, config: Config) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw RefineError.invalidURL
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0,
            "max_tokens": 2048
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RefineError.apiError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw RefineError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testConnection(config: Config) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw RefineError.invalidURL
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": "Hello"]
            ],
            "max_tokens": 10
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RefineError.apiError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RefineError.emptyResponse
        }

        return content
    }

    enum RefineError: LocalizedError {
        case invalidURL
        case apiError
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid API URL"
            case .apiError: "API request failed. Check your API key and base URL."
            case .emptyResponse: "API returned an empty response"
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/LLMRefiner.swift
git commit -m "feat: add LLMRefiner with OpenAI-compatible API client and conservative system prompt"
```

---

### Task 8: CapsuleContentView (SwiftUI)

**Files:**
- Create: `Sources/VoiceInput/CapsuleContentView.swift`

- [ ] **Step 1: Create CapsuleContentView.swift**

```swift
import SwiftUI

struct CapsuleContentView: View {
    let rmsLevel: Float
    let transcription: String
    let isRefining: Bool

    var body: some View {
        HStack(spacing: 16) {
            WaveformView(rmsLevel: rmsLevel)
                .frame(width: 44, height: 32)

            if isRefining {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.small)
                    Text("Refining...")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 15))
                }
                .frame(minWidth: 160, maxWidth: 560, alignment: .leading)
            } else {
                Text(transcription.isEmpty ? " " : transcription)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 160, maxWidth: 560, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: transcription)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }
}

struct WaveformView: View {
    let rmsLevel: Float

    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    @State private var envelope: Float = 0
    @State private var jitters: [Float] = [0, 0, 0, 0, 0]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { _ in
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0, green: 0.478, blue: 1.0),
                                         Color(red: 0.35, green: 0.78, blue: 0.98)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3.5, height: barHeight(for: i))
                }
            }
            .frame(width: 44, height: 32)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let attack: Float = 0.40
        let release: Float = 0.15
        let coefficient = rmsLevel > envelope ? attack : release
        envelope = envelope * (1 - coefficient) + rmsLevel * coefficient

        jitters[index] = Float.random(in: -0.04...0.04)

        let weighted = envelope * weights[index] * (1 + jitters[index])
        let clamped = max(3, min(weighted * 32, 32))
        return CGFloat(clamped)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/CapsuleContentView.swift
git commit -m "feat: add CapsuleContentView with RMS-driven waveform and elastic transcription label"
```

---

### Task 9: CapsuleController (NSPanel)

**Files:**
- Create: `Sources/VoiceInput/CapsuleController.swift`

- [ ] **Step 1: Create CapsuleController.swift**

```swift
import AppKit
import SwiftUI

final class CapsuleController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<CapsuleContentView>?

    func show(rmsLevel: Float = 0, transcription: String = "", isRefining: Bool = false) {
        if panel == nil {
            createPanel()
        }
        updateContent(rmsLevel: rmsLevel, transcription: transcription, isRefining: isRefining)
        positionPanel(animated: true)
    }

    func update(rmsLevel: Float, transcription: String) {
        guard let hostingView, let panel, panel.isVisible else { return }
        hostingView.rootView = CapsuleContentView(
            rmsLevel: rmsLevel,
            transcription: transcription,
            isRefining: false
        )
        adjustPanelWidth()
    }

    func showRefining(transcription: String) {
        guard let hostingView, let panel, panel.isVisible else { return }
        hostingView.rootView = CapsuleContentView(
            rmsLevel: 0,
            transcription: transcription,
            isRefining: true
        )
        adjustPanelWidth()
    }

    func dismiss() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setContentSize(NSSize(width: panel.frame.width * 0.9, height: panel.frame.height * 0.9))
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            self?.hostingView?.rootView = CapsuleContentView(rmsLevel: 0, transcription: "", isRefining: false)
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func createPanel() {
        let contentView = CapsuleContentView(rmsLevel: 0, transcription: "", isRefining: false)
        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 28
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        self.panel = panel
    }

    private func updateContent(rmsLevel: Float, transcription: String, isRefining: Bool) {
        hostingView?.rootView = CapsuleContentView(
            rmsLevel: rmsLevel,
            transcription: transcription,
            isRefining: isRefining
        )
    }

    private func positionPanel(animated: Bool) {
        guard let panel else { return }

        let screen = currentScreen()
        let screenFrame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY + 40

        let targetFrame = NSRect(x: x, y: y, width: panelWidth, height: 56)

        if animated {
            panel.alphaValue = 0
            panel.setFrame(targetFrame, display: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.allowsImplicitAnimation = true
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }

        panel.orderFront(nil)
    }

    private func adjustPanelWidth() {
        guard let hostingView, let panel else { return }
        let idealWidth = hostingView.intrinsicContentSize.width
        let clamped = min(max(idealWidth, 260), 660)
        let screen = currentScreen()
        let screenFrame = screen.visibleFrame
        let newOrigin = NSPoint(x: screenFrame.midX - clamped / 2, y: panel.frame.origin.y)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(NSRect(origin: newOrigin, size: NSSize(width: clamped, height: 56)), display: true)
        }
    }

    private func currentScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.screens.first!
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/CapsuleController.swift
git commit -m "feat: add CapsuleController with NSPanel, spring entry, elastic width, and scale exit"
```

---

### Task 10: SettingsWindowView

**Files:**
- Create: `Sources/VoiceInput/SettingsWindowView.swift`

- [ ] **Step 1: Create SettingsWindowView.swift**

```swift
import SwiftUI

struct SettingsWindowView: View {
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var isTesting = false
    @State private var testResult: String?

    private let defaults = UserDefaults.standard

    init() {
        _baseURL = State(initialValue: UserDefaults.standard.string(forKey: "llmBaseURL") ?? "https://api.deepseek.com/v1")
        _apiKey = State(initialValue: UserDefaults.standard.string(forKey: "llmApiKey") ?? "")
        _model = State(initialValue: UserDefaults.standard.string(forKey: "llmModel") ?? "deepseek-v4-flash")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Base URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, newValue in
                        apiKey = newValue
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("deepseek-v4-flash", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("Success") ? .green : .red)
            }

            HStack(spacing: 8) {
                Button(action: testConnection) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                    }
                    Text("Test")
                }
                .disabled(isTesting)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let config = LLMRefiner.Config(baseURL: baseURL, apiKey: apiKey, model: model)
        let refiner = LLMRefiner()

        Task {
            defer { isTesting = false }
            do {
                let response = try await refiner.testConnection(config: config)
                testResult = "Success: \(response)"
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func save() {
        defaults.set(baseURL, forKey: "llmBaseURL")
        defaults.set(apiKey, forKey: "llmApiKey")
        defaults.set(model, forKey: "llmModel")
        testResult = "Saved"

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) {
            if testResult == "Saved" {
                testResult = nil
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/SettingsWindowView.swift
git commit -m "feat: add SettingsWindowView with API config fields, test connection, and save"
```

---

### Task 11: RecordingCoordinator

**Files:**
- Create: `Sources/VoiceInput/RecordingCoordinator.swift`

- [ ] **Step 1: Create RecordingCoordinator.swift**

```swift
import Foundation
import Observation

final class RecordingCoordinator {
    private let eventMonitor = GlobalEventMonitor()
    private let audioCapture = AudioCaptureManager()
    private let textInjector = TextInjector()
    private let llmRefiner = LLMRefiner()
    private var speechRecognizer: SpeechRecognizer

    private let capsule = CapsuleController()
    private var isRecording = false
    private var hasDetectedSpeech = false

    var menuBarFlashCallback: ((MenuBarFlash) -> Void)?

    enum MenuBarFlash {
        case warning
        case amber
    }

    init() {
        let locale = UserDefaults.standard.string(forKey: "recognitionLocale") ?? "zh-CN"
        speechRecognizer = SpeechRecognizer(localeIdentifier: locale)
        setupEventMonitor()
    }

    func setLocale(_ identifier: String) {
        speechRecognizer.setLocale(identifier)
    }

    private func setupEventMonitor() {
        eventMonitor.onPress = { [weak self] in
            self?.startRecording()
        }
        eventMonitor.onRelease = { [weak self] in
            self?.stopRecording()
        }
    }

    func startMonitoring() -> Bool {
        eventMonitor.start()
    }

    func cancel() {
        eventMonitor.stop()
        if isRecording {
            audioCapture.stop()
            speechRecognizer.stopRecognition()
            capsule.dismiss()
            isRecording = false
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        hasDetectedSpeech = false

        capsule.show(rmsLevel: 0, transcription: "", isRefining: false)

        do {
            let request = speechRecognizer.audioBufferRequest()
            audioCapture.setRecognitionRequest(request)
            try speechRecognizer.startRecognition()
            try audioCapture.start()

            observeStreamingState()
        } catch {
            capsule.dismiss()
            isRecording = false
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        audioCapture.stop()
        speechRecognizer.stopRecognition()

        let finalText = speechRecognizer.finalText.isEmpty
            ? speechRecognizer.partialText
            : speechRecognizer.finalText

        guard !finalText.isEmpty, hasDetectedSpeech else {
            capsule.dismiss()
            menuBarFlashCallback?(.warning)
            return
        }

        if isLLMEnabled() {
            refineThenInject(text: finalText)
        } else {
            capsule.dismiss()
            textInjector.inject(text: finalText)
        }
    }

    private func isLLMEnabled() -> Bool {
        guard UserDefaults.standard.bool(forKey: "llmEnabled") else { return false }
        let apiKey = UserDefaults.standard.string(forKey: "llmApiKey") ?? ""
        let baseURL = UserDefaults.standard.string(forKey: "llmBaseURL") ?? ""
        return !apiKey.isEmpty && !baseURL.isEmpty
    }

    private func refineThenInject(text: String) {
        capsule.showRefining(transcription: text)

        let config = LLMRefiner.Config(
            baseURL: UserDefaults.standard.string(forKey: "llmBaseURL") ?? "",
            apiKey: UserDefaults.standard.string(forKey: "llmApiKey") ?? "",
            model: UserDefaults.standard.string(forKey: "llmModel") ?? "deepseek-v4-flash"
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                let refined = try await self.llmRefiner.refine(text: text, config: config)
                await MainActor.run {
                    self.capsule.dismiss()
                    self.textInjector.inject(text: refined)
                }
            } catch {
                await MainActor.run {
                    self.capsule.dismiss()
                    self.textInjector.inject(text: text)
                    self.menuBarFlashCallback?(.amber)
                }
            }
        }
    }

    private func observeStreamingState() {
        withObservationTracking { [weak self] in
            guard let self, self.isRecording else { return }
            let rms = self.audioCapture.rmsLevel
            let transcription = self.speechRecognizer.partialText
            if rms > 0.01 { self.hasDetectedSpeech = true }
            self.capsule.update(rmsLevel: rms, transcription: transcription)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isRecording else { return }
                self.observeStreamingState()
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/RecordingCoordinator.swift
git commit -m "feat: add RecordingCoordinator with full state machine and LLM refinement path"
```

---

### Task 12: AppDelegate — Full Wiring

**Files:**
- Modify: `Sources/VoiceInput/AppDelegate.swift` (replace stub)

- [ ] **Step 1: Rewrite AppDelegate.swift**

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: RecordingCoordinator?
    private var settingsWindow: NSWindow?

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupCoordinator()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.cancel()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
            button.action = #selector(statusBarClicked)
            button.sendAction(on: [.leftMouseUp])
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let languageMenu = NSMenu()
        let languages: [(String, String)] = [
            ("English", "en-US"),
            ("简体中文", "zh-CN"),
            ("繁體中文", "zh-TW"),
            ("日本語", "ja-JP"),
            ("한국어", "ko-KR")
        ]

        let currentLocale = defaults.string(forKey: "recognitionLocale") ?? "zh-CN"

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        menu.addItem(languageItem)
        menu.setSubmenu(languageMenu, for: languageItem)

        for (label, locale) in languages {
            let item = NSMenuItem(title: label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.state = (locale == currentLocale) ? .on : .off
            item.representedObject = locale
            languageMenu.addItem(item)
        }

        menu.addItem(.separator())

        let llmMenu = NSMenu()
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        menu.addItem(llmItem)
        menu.setSubmenu(llmMenu, for: llmItem)

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleLLM), keyEquivalent: "")
        enabledItem.state = defaults.bool(forKey: "llmEnabled") ? .on : .off
        llmMenu.addItem(enabledItem)

        llmMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Coordinator

    private func setupCoordinator() {
        coordinator = RecordingCoordinator()

        if !(coordinator?.startMonitoring() ?? false) {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Voice Input needs Accessibility permission in System Settings to monitor the Fn key."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else {
                NSApp.terminate(nil)
            }
        }

        coordinator?.menuBarFlashCallback = { [weak self] flash in
            DispatchQueue.main.async {
                self?.flashIcon(flash)
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let locale = sender.representedObject as? String else { return }
        defaults.set(locale, forKey: "recognitionLocale")
        coordinator?.setLocale(locale)
        buildMenu()
    }

    @objc private func toggleLLM() {
        let current = defaults.bool(forKey: "llmEnabled")
        defaults.set(!current, forKey: "llmEnabled")
        buildMenu()
    }

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Settings"
        window.contentView = NSHostingView(rootView: SettingsWindowView())
        window.center()
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func statusBarClicked() {
        // Clicking the status bar icon shows the menu (default behavior)
    }

    // MARK: - Icon Flashing

    private func flashIcon(_ flash: RecordingCoordinator.MenuBarFlash) {
        let color: NSColor = switch flash {
        case .warning: .systemOrange
        case .amber: .systemOrange
        }

        statusItem?.button?.contentTintColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) { [weak self] in
            self?.statusItem?.button?.contentTintColor = nil
        }
    }
}

```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceInput/AppDelegate.swift
git commit -m "feat: wire AppDelegate with status bar, menu, permissions, and coordinator lifecycle"
```

---

### Task 13: Build & Smoke Test

**Files:** None new

- [ ] **Step 1: Full release build**

Run: `make build`
Expected: Successful build, ad-hoc signed `.app` bundle at `.build/release/VoiceInput.app`.

- [ ] **Step 2: Verify app bundle structure**

Run: `ls -la .build/release/VoiceInput.app/Contents/`
Expected: `MacOS/`, `Info.plist`, `PkgInfo`

- [ ] **Step 3: Verify LSUIElement is set**

Run: `plutil -p .build/release/VoiceInput.app/Contents/Info.plist | grep LSUIElement`
Expected: `"LSUIElement" => 1`

- [ ] **Step 4: Start the app**

Run: `make run`
Expected: App opens. No Dock icon. Menu bar shows mic icon. Click icon → menu appears with language options, LLM submenu, Quit.

- [ ] **Step 5: Grant Accessibility permission**

Go to System Settings → Privacy & Security → Accessibility → add VoiceInput.app.

- [ ] **Step 6: Test recording flow**

1. Ensure mic permission is granted (System Settings → Privacy & Security → Microphone)
2. Select "简体中文" in the menu bar
3. Click a text field in any app
4. Hold Fn key for >200ms → capsule should appear at screen bottom with waveform animation
5. Speak → waveform bars should react to voice level, transcription should appear
6. Release Fn → text should paste into the focused field via Cmd+V
7. Check clipboard is restored (paste into another app to verify original content)

- [ ] **Step 7: Test LLM refinement**

1. Open LLM Settings (Cmd+, or menu → LLM Refinement → Settings)
2. Enter API Base URL, API Key, Model
3. Click Test → verify "Success" appears
4. Click Save
5. Enable LLM Refinement in menu
6. Record speech → on release, capsule should show "Refining..." → refined text pasted

- [ ] **Step 8: Commit final state**

```bash
git add . && git commit -m "chore: final build verification — all features functional"
```
