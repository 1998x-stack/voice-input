import Foundation
import Observation

final class RecordingCoordinator: @unchecked Sendable {
    private let eventMonitor = GlobalEventMonitor()
    private let audioCapture = AudioCaptureManager()
    private let textInjector = TextInjector()
    private let llmRefiner = LLMRefiner()
    private var speechRecognizer: SpeechRecognizer

    private let capsule = CapsuleController()
    private var isRecording = false
    private var hasDetectedSpeech = false
    private var refinementTask: Task<Void, Never>?

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
        refinementTask?.cancel()
        refinementTask = nil
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

        refinementTask?.cancel()
        refinementTask = nil

        isRecording = true
        hasDetectedSpeech = false

        capsule.show(rmsLevel: 0, transcription: "", isRefining: false)

        do {
            let request = try speechRecognizer.startRecognition()
            audioCapture.setRecognitionRequest(request)
            try audioCapture.start()

            observeStreamingState()
        } catch {
            speechRecognizer.stopRecognition()
            capsule.dismiss()
            isRecording = false
        }
    }

    private func abortRecording() {
        isRecording = false
        audioCapture.stop()
        speechRecognizer.stopRecognition()
        capsule.dismiss()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        let capturedText = speechRecognizer.partialText

        audioCapture.stop()
        speechRecognizer.stopRecognition()

        guard !capturedText.isEmpty, hasDetectedSpeech else {
            capsule.dismiss()
            menuBarFlashCallback?(.warning)
            return
        }

        if isLLMEnabled() {
            refineThenInject(text: capturedText)
        } else {
            capsule.dismiss()
            textInjector.inject(text: capturedText)
        }
    }

    private func llmApiKey() -> String {
        ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "llmApiKey")
            ?? ""
    }

    private func isLLMEnabled() -> Bool {
        guard UserDefaults.standard.bool(forKey: "llmEnabled") else { return false }
        let apiKey = llmApiKey()
        let baseURL = UserDefaults.standard.string(forKey: "llmBaseURL") ?? ""
        return !apiKey.isEmpty && !baseURL.isEmpty
    }

    private func refineThenInject(text: String) {
        capsule.showRefining(transcription: text)

        let config = LLMRefiner.Config(
            baseURL: UserDefaults.standard.string(forKey: "llmBaseURL") ?? "",
            apiKey: llmApiKey(),
            model: UserDefaults.standard.string(forKey: "llmModel") ?? "deepseek-v4-flash"
        )

        refinementTask = Task { [weak self] in
            guard let self else { return }
            do {
                let refined = try await self.llmRefiner.refine(text: text, config: config)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !self.isRecording else { return }
                    self.capsule.dismiss()
                    self.textInjector.inject(text: refined)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !self.isRecording else { return }
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
            if self.speechRecognizer.recognitionError != nil {
                self.capsule.update(rmsLevel: 0, transcription: "Recognition failed")
                self.menuBarFlashCallback?(.warning)
                self.abortRecording()
                return
            }
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
