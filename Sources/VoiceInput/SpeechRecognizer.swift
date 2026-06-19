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
    private var recognitionTask: SFSpeechRecognitionTask?
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
