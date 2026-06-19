import XCTest
import Speech
@testable import VoiceInput

final class SpeechRecognizerTests: XCTestCase {

    // MARK: - Error descriptions

    func testRecognitionError_unavailable() {
        XCTAssertEqual(
            SpeechRecognizer.RecognitionError.unavailable.errorDescription,
            "Speech recognition is not available. Check network or locale support."
        )
    }

    // MARK: - Initialization

    func testInit_setsLocaleIdentifier() {
        let recognizer = SpeechRecognizer(localeIdentifier: "en-US")
        XCTAssertEqual(recognizer.localeIdentifier, "en-US")
    }

    func testInit_defaultChineseLocale() {
        let recognizer = SpeechRecognizer(localeIdentifier: "zh-CN")
        XCTAssertEqual(recognizer.localeIdentifier, "zh-CN")
        // isAvailable may be true or false depending on network/download state
    }

    // MARK: - State reset on start

    func testStartRecognition_clearsError() throws {
        let recognizer = SpeechRecognizer(localeIdentifier: "en-US")
        recognizer.recognitionError = "previous error"

        // startRecognition throws if recognizer is unavailable (no network/permission)
        // Skip the full test if unavailable
        guard recognizer.isAvailable else {
            throw XCTSkip("Speech recognition not available in this environment")
        }

        _ = try recognizer.startRecognition()
        XCTAssertNil(recognizer.recognitionError)
        XCTAssertTrue(recognizer.partialText.isEmpty)
        XCTAssertTrue(recognizer.finalText.isEmpty)
    }

    // MARK: - Locale switching

    func testSetLocale_sameIdentifier_noop() {
        let recognizer = SpeechRecognizer(localeIdentifier: "en-US")
        // Should not crash or change state
        recognizer.setLocale("en-US")
        XCTAssertEqual(recognizer.localeIdentifier, "en-US")
    }

    func testSetLocale_differentIdentifier_updates() {
        let recognizer = SpeechRecognizer(localeIdentifier: "en-US")
        recognizer.setLocale("zh-CN")
        XCTAssertEqual(recognizer.localeIdentifier, "zh-CN")
    }

    func testSetLocale_invalidFallsBack() {
        let recognizer = SpeechRecognizer(localeIdentifier: "zz-XX")
        // Invalid locale — recognizer will be nil, isAvailable should be false
        XCTAssertFalse(recognizer.isAvailable)
    }
}
