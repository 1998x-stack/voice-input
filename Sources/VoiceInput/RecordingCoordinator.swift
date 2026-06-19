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
            let request = try speechRecognizer.startRecognition()
            audioCapture.setRecognitionRequest(request)
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
