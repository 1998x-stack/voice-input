import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: RecordingCoordinator?
    private var settingsWindow: NSWindow?

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupCoordinator()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.cancel()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
            button.action = #selector(statusBarClicked)
            button.sendAction(on: [.leftMouseUp])
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let languageMenu = NSMenu()
        let languages: [(String, String)] = [
            ("English", "en-US"),
            ("简体中文", "zh-CN"),
            ("繁體中文", "zh-TW"),
            ("日本語", "ja-JP"),
            ("한국어", "ko-KR")
        ]

        let currentLocale = defaults.string(forKey: "recognitionLocale") ?? "zh-CN"

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        menu.addItem(languageItem)
        menu.setSubmenu(languageMenu, for: languageItem)

        for (label, locale) in languages {
            let item = NSMenuItem(title: label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.state = (locale == currentLocale) ? .on : .off
            item.representedObject = locale
            languageMenu.addItem(item)
        }

        menu.addItem(.separator())

        let llmMenu = NSMenu()
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        menu.addItem(llmItem)
        menu.setSubmenu(llmMenu, for: llmItem)

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleLLM), keyEquivalent: "")
        enabledItem.state = defaults.bool(forKey: "llmEnabled") ? .on : .off
        llmMenu.addItem(enabledItem)

        llmMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Coordinator

    private func setupCoordinator() {
        coordinator = RecordingCoordinator()

        if !(coordinator?.startMonitoring() ?? false) {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Voice Input needs Accessibility permission in System Settings to monitor the Fn key."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else {
                NSApp.terminate(nil)
            }
        }

        coordinator?.menuBarFlashCallback = { [weak self] flash in
            DispatchQueue.main.async {
                self?.flashIcon(flash)
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let locale = sender.representedObject as? String else { return }
        defaults.set(locale, forKey: "recognitionLocale")
        coordinator?.setLocale(locale)
        buildMenu()
    }

    @objc private func toggleLLM() {
        let current = defaults.bool(forKey: "llmEnabled")
        defaults.set(!current, forKey: "llmEnabled")
        buildMenu()
    }

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Settings"
        window.contentView = NSHostingView(rootView: SettingsWindowView())
        window.center()
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func statusBarClicked() {
        // Clicking the status bar icon shows the menu (default behavior)
    }

    // MARK: - Icon Flashing

    private func flashIcon(_ flash: RecordingCoordinator.MenuBarFlash) {
        let color: NSColor = switch flash {
        case .warning: .systemOrange
        case .amber: .systemOrange
        }

        statusItem?.button?.contentTintColor = color
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) { [weak self] in
            self?.statusItem?.button?.contentTintColor = nil
        }
    }
}
