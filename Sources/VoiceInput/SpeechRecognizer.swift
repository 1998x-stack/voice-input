import Speech
import Foundation
import Observation

@Observable
final class SpeechRecognizer {
    var partialText: String = ""
    var finalText: String = ""
    var isAvailable: Bool = false
    var recognitionError: String?
    var localeIdentifier: String

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID: Int = 0

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
        refreshRecognizer()
    }

    func setLocale(_ identifier: String) {
        guard identifier != localeIdentifier else { return }
        stopRecognition()
        localeIdentifier = identifier
        refreshRecognizer()
    }

    private func refreshRecognizer() {
        let locale = Locale(identifier: localeIdentifier)
        recognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = recognizer?.isAvailable ?? false
    }

    func startRecognition() throws -> SFSpeechAudioBufferRecognitionRequest {
        guard let recognizer, recognizer.isAvailable else {
            throw RecognitionError.unavailable
        }

        stopRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        sessionID += 1
        let currentSession = sessionID
        partialText = ""
        finalText = ""
        recognitionError = nil

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.sessionID == currentSession else { return }
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finalText = result.bestTranscription.formattedString
                    }
                }
                if let error {
                    self.recognitionError = error.localizedDescription
                }
            }
        }

        return request
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
