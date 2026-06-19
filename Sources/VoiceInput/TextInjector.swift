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
