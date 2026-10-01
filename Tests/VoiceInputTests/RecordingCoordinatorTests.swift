import XCTest
@testable import VoiceInput

final class RecordingCoordinatorTests: XCTestCase {

    private var coordinator: RecordingCoordinator!
    private let defaults = UserDefaults.standard

    override func setUp() {
        coordinator = RecordingCoordinator()
        // Save and clear relevant UserDefaults for clean test state
        defaults.removeObject(forKey: "llmEnabled")
        defaults.removeObject(forKey: "llmApiKey")
        defaults.removeObject(forKey: "llmBaseURL")
        defaults.removeObject(forKey: "llmModel")
        unsetenv("DEEPSEEK_API_KEY")
    }

    override func tearDown() {
        coordinator.cancel()
        coordinator = nil
        defaults.removeObject(forKey: "llmEnabled")
        defaults.removeObject(forKey: "llmApiKey")
        defaults.removeObject(forKey: "llmBaseURL")
        defaults.removeObject(forKey: "llmModel")
        unsetenv("DEEPSEEK_API_KEY")
    }

    // MARK: - isLLMEnabled

    func testIsLLMEnabled_defaultsToFalse() {
        defaults.set(false, forKey: "llmEnabled")
        defaults.set("", forKey: "llmApiKey")
        defaults.set("", forKey: "llmBaseURL")
        XCTAssertFalse(coordinator.isLLMEnabled())
    }

    func testIsLLMEnabled_falseWhenDisabled() {
        defaults.set(false, forKey: "llmEnabled")
        defaults.set("sk-test", forKey: "llmApiKey")
        defaults.set("https://api.test.com/v1", forKey: "llmBaseURL")
        XCTAssertFalse(coordinator.isLLMEnabled())
    }

    func testIsLLMEnabled_falseWithoutApiKey() {
        defaults.set(true, forKey: "llmEnabled")
        defaults.set("", forKey: "llmApiKey")
        defaults.set("https://api.test.com/v1", forKey: "llmBaseURL")
        XCTAssertFalse(coordinator.isLLMEnabled())
    }

    func testIsLLMEnabled_falseWithoutBaseURL() {
        defaults.set(true, forKey: "llmEnabled")
        defaults.set("sk-test", forKey: "llmApiKey")
        defaults.set("", forKey: "llmBaseURL")
        XCTAssertFalse(coordinator.isLLMEnabled())
    }

    func testIsLLMEnabled_trueWhenFullyConfigured() {
        defaults.set(true, forKey: "llmEnabled")
        defaults.set("sk-test", forKey: "llmApiKey")
        defaults.set("https://api.test.com/v1", forKey: "llmBaseURL")
        XCTAssertTrue(coordinator.isLLMEnabled())
    }

    // MARK: - llmApiKey

    func testLlmApiKey_returnsUserDefaultsValue() {
        defaults.set("userdefaults-key", forKey: "llmApiKey")
        unsetenv("DEEPSEEK_API_KEY")
        XCTAssertEqual(coordinator.llmApiKey(), "userdefaults-key")
    }

    func testLlmApiKey_returnsEmptyWhenNotSet() {
        defaults.removeObject(forKey: "llmApiKey")
        unsetenv("DEEPSEEK_API_KEY")
        XCTAssertEqual(coordinator.llmApiKey(), "")
    }

    // MARK: - MenuBarFlash

    func testMenuBarFlash_warningExists() {
        let flash: RecordingCoordinator.MenuBarFlash = .warning
        _ = flash // Ensure enum case is accessible
    }

    func testMenuBarFlash_amberExists() {
        let flash: RecordingCoordinator.MenuBarFlash = .amber
        _ = flash
    }

    // MARK: - Start Monitoring

    func testStartMonitoring_returnsBool() {
        let result = coordinator.startMonitoring()
        // May fail without Accessibility permission, but should not crash
        _ = result
    }

    // MARK: - Cancel

    func testCancel_whenNotRecording_isNoop() {
        coordinator.cancel() // Should not crash
    }

    func testCancel_stopStart_stopMonitoring_cycle() {
        _ = coordinator.startMonitoring()
        coordinator.cancel()
        _ = coordinator.startMonitoring()
        coordinator.cancel()
        // Should not crash
    }

    // MARK: - setLocale

    func testSetLocale_updatesWithoutCrash() {
        coordinator.setLocale("en-US")
        coordinator.setLocale("zh-CN")
        coordinator.setLocale("ja-JP")
        // Should not crash
    }
}
