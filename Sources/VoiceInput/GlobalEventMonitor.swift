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
        CGPreflightListenEventAccess()
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
        }

        DispatchQueue.main.async { [weak self] in
            self?.onRelease?()
        }

        return nil
    }
}
