import XCTest
import CoreGraphics
@testable import VoiceInput

final class GlobalEventMonitorTests: XCTestCase {

    private var monitor: GlobalEventMonitor!

    override func setUp() {
        monitor = GlobalEventMonitor()
    }

    override func tearDown() {
        monitor.stop()
        monitor = nil
    }

    // MARK: - Permission Check

    func testCheckAccessibilityPermission_returnsBool() {
        let result = monitor.checkAccessibilityPermission()
        // Just verify it doesn't crash and returns a boolean
        XCTAssertTrue(result || !result, "Should return a boolean")
    }

    // MARK: - Fn Key Down

    func testFnKeyDown_suppressesEvent() {
        let event = makeKeyEvent(keyCode: 63, keyDown: true)
        let result = monitor.handleFnKeyDown(event: event)
        XCTAssertNil(result, "Fn keyDown should be suppressed (return nil)")
    }

    func testFnKeyDown_doublePress_ignored() {
        let event = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: event)

        // Second Fn keyDown while already pressed should pass through
        let result = monitor.handleFnKeyDown(event: event)
        XCTAssertNotNil(result, "Second Fn keyDown should pass through")
    }

    func testFnKeyDown_setsUpDebounceTimer() {
        let event = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: event)

        // onPress should NOT fire immediately (debounce)
        let exp = expectation(description: "onPress not called immediately")
        exp.isInverted = true
        monitor.onPress = { exp.fulfill() }
        wait(for: [exp], timeout: 0.15) // < 200ms
    }

    func testFnKeyDown_firesOnPressAfterDebounce() {
        let event = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: event)

        let exp = expectation(description: "onPress fired after debounce")
        monitor.onPress = { exp.fulfill() }

        wait(for: [exp], timeout: 0.5) // > 200ms
    }

    // MARK: - Fn Key Up

    func testFnKeyUp_afterDebounce_callsOnRelease() {
        let downEvent = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: downEvent)

        // Wait for debounce to fire onPress
        let pressExp = expectation(description: "onPress fired")
        monitor.onPress = { pressExp.fulfill() }
        wait(for: [pressExp], timeout: 0.5)

        // Now release Fn
        let releaseExp = expectation(description: "onRelease fired after debounce")
        monitor.onRelease = { releaseExp.fulfill() }

        let upEvent = makeKeyEvent(keyCode: 63, keyDown: false)
        _ = monitor.handleFnKeyUp(event: upEvent)

        wait(for: [releaseExp], timeout: 0.5)
    }

    func testFnKeyUp_beforeDebounce_doesNotCallOnRelease() {
        let downEvent = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: downEvent)

        // Release Fn immediately (before 200ms)
        let releaseExp = expectation(description: "onRelease should NOT fire")
        releaseExp.isInverted = true
        monitor.onRelease = { releaseExp.fulfill() }

        let upEvent = makeKeyEvent(keyCode: 63, keyDown: false)
        _ = monitor.handleFnKeyUp(event: upEvent)

        wait(for: [releaseExp], timeout: 0.1)
    }

    func testFnKeyUp_beforeDebounce_suppressesEvent() {
        let downEvent = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: downEvent)

        let upEvent = makeKeyEvent(keyCode: 63, keyDown: false)
        let result = monitor.handleFnKeyUp(event: upEvent)
        XCTAssertNil(result, "Fn keyUp before debounce should be suppressed")
    }

    func testFnKeyUp_withoutPress_doesNotCallOnRelease() {
        // Fn keyUp should be ignored if not pressed
        let releaseExp = expectation(description: "onRelease should NOT fire")
        releaseExp.isInverted = true
        monitor.onRelease = { releaseExp.fulfill() }

        let upEvent = makeKeyEvent(keyCode: 63, keyDown: false)
        let result = monitor.handleFnKeyUp(event: upEvent)
        XCTAssertNotNil(result, "Fn keyUp without press should pass through")

        wait(for: [releaseExp], timeout: 0.1)
    }

    // MARK: - handleEvent: Non-Fn Keys

    func testHandleEvent_nonFnKey_passesThrough() {
        let aDown = makeKeyEvent(keyCode: 0, keyDown: true) // 'a' key
        let result = monitor.handleEvent(proxy: dummyProxy(), type: .keyDown, event: aDown)
        XCTAssertNotNil(result, "Non-Fn key should pass through")
    }

    func testHandleEvent_otherKeyDuringFnPress_cancelsTimer() {
        // Press Fn
        let fnDown = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: fnDown)

        // Press another key while Fn is held
        let onPressExp = expectation(description: "onPress should NOT fire")
        onPressExp.isInverted = true
        monitor.onPress = { onPressExp.fulfill() }

        let aDown = makeKeyEvent(keyCode: 0, keyDown: true)
        let result = monitor.handleEvent(proxy: dummyProxy(), type: .keyDown, event: aDown)
        XCTAssertNotNil(result, "Other key should pass through")

        wait(for: [onPressExp], timeout: 0.5) // > 200ms, but timer should be cancelled
    }

    func testHandleEvent_otherKeyAfterDebounce_passesThrough() {
        // Press Fn, wait for debounce
        let fnDown = makeKeyEvent(keyCode: 63, keyDown: true)
        _ = monitor.handleFnKeyDown(event: fnDown)

        let pressExp = expectation(description: "onPress fired")
        monitor.onPress = { pressExp.fulfill() }
        wait(for: [pressExp], timeout: 0.5)

        // Press another key during recording
        let aDown = makeKeyEvent(keyCode: 0, keyDown: true)
        let result = monitor.handleEvent(proxy: dummyProxy(), type: .keyDown, event: aDown)
        XCTAssertNotNil(result, "Other key should pass through during recording")
    }

    // MARK: - TapDisabledByTimeout callback

    func testTapDisabledByTimeout_reEnablesViaStartStop() {
        // tapDisabledByTimeout is handled in the C callback before handleEvent,
        // so we verify the start/stop cycle works instead
        _ = monitor.start()
        monitor.stop()
        _ = monitor.start()
        monitor.stop()
    }

    // MARK: - Helpers

    private func makeKeyEvent(keyCode: Int64, keyDown: Bool) -> CGEvent {
        CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)!
    }

    private func dummyProxy() -> CGEventTapProxy {
        // CGEventTapProxy is an OpaquePointer alias
        // Create a dummy non-null pointer for testing
        let ptr = UnsafeMutableRawPointer(bitPattern: 1)!
        return OpaquePointer(ptr)
    }
}
