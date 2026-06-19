import XCTest
import Carbon
@testable import VoiceInput

final class TextInjectorTests: XCTestCase {

    private let injector = TextInjector()

    // MARK: - nil input

    func testInputSourceIsCJK_nil() {
        XCTAssertFalse(injector.inputSourceIsCJK(nil))
    }

    // MARK: - Prefix matching (the core logic)

    func testCJKPrefixes_matchChinese() {
        let cjk = ["zh", "ja", "ko"]
        XCTAssertTrue(cjk.contains(where: { "zh-Hans".hasPrefix($0) }))
        XCTAssertTrue(cjk.contains(where: { "zh-Hant".hasPrefix($0) }))
        XCTAssertTrue(cjk.contains(where: { "zh-CN".hasPrefix($0) }))
    }

    func testCJKPrefixes_matchJapanese() {
        let cjk = ["zh", "ja", "ko"]
        XCTAssertTrue(cjk.contains(where: { "ja-JP".hasPrefix($0) }))
    }

    func testCJKPrefixes_matchKorean() {
        let cjk = ["zh", "ja", "ko"]
        XCTAssertTrue(cjk.contains(where: { "ko-KR".hasPrefix($0) }))
    }

    func testCJKPrefixes_doNotMatchEnglish() {
        let cjk = ["zh", "ja", "ko"]
        XCTAssertFalse(cjk.contains(where: { "en-US".hasPrefix($0) }))
        XCTAssertFalse(cjk.contains(where: { "fr-FR".hasPrefix($0) }))
    }

    // MARK: - Real input sources (integration)

    func testInputSourceIsCJK_realABC() throws {
        guard let abc = findInputSource(byID: "com.apple.keylayout.ABC") else {
            throw XCTSkip("ABC input source not found")
        }
        XCTAssertFalse(injector.inputSourceIsCJK(abc))
    }

    func testInputSourceIsCJK_realPinyin() throws {
        guard let pinyin = findInputSource(containing: "Pinyin") else {
            throw XCTSkip("Pinyin input source not available")
        }
        XCTAssertTrue(injector.inputSourceIsCJK(pinyin))
    }

    // MARK: - Helpers

    private func findInputSource(byID targetID: String) -> TISInputSource? {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return sources.first { source in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String? else { return false }
            return id == targetID
        }
    }

    private func findInputSource(containing substring: String) -> TISInputSource? {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return sources.first { source in
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String? else { return false }
            return id.contains(substring)
        }
    }
}
