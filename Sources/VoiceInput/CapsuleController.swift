import AppKit
import SwiftUI

final class CapsuleController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<CapsuleContentView>?
    private var showGeneration: UInt = 0

    func show(rmsLevel: Float = 0, transcription: String = "", isRefining: Bool = false) {
        showGeneration &+= 1
        if panel == nil {
            createPanel()
        }
        updateContent(rmsLevel: rmsLevel, transcription: transcription, isRefining: isRefining)
        positionPanel(animated: true)
    }

    func update(rmsLevel: Float, transcription: String) {
        guard let hostingView, let panel, panel.isVisible else { return }
        hostingView.rootView = CapsuleContentView(
            rmsLevel: rmsLevel,
            transcription: transcription,
            isRefining: false
        )
        adjustPanelWidth()
    }

    func showRefining(transcription: String) {
        guard let hostingView, let panel, panel.isVisible else { return }
        hostingView.rootView = CapsuleContentView(
            rmsLevel: 0,
            transcription: transcription,
            isRefining: true
        )
        adjustPanelWidth()
    }

    func dismiss() {
        guard let panel, panel.isVisible else { return }
        let generationAtDismiss = showGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setContentSize(NSSize(width: panel.frame.width * 0.9, height: panel.frame.height * 0.9))
        } completionHandler: { [weak self] in
            guard let self, self.showGeneration == generationAtDismiss else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            self.hostingView?.rootView = CapsuleContentView(rmsLevel: 0, transcription: "", isRefining: false)
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func createPanel() {
        let contentView = CapsuleContentView(rmsLevel: 0, transcription: "", isRefining: false)
        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 28
        effectView.layer?.masksToBounds = true
        panel.contentView = effectView

        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        self.panel = panel
    }

    private func updateContent(rmsLevel: Float, transcription: String, isRefining: Bool) {
        hostingView?.rootView = CapsuleContentView(
            rmsLevel: rmsLevel,
            transcription: transcription,
            isRefining: isRefining
        )
    }

    private func positionPanel(animated: Bool) {
        guard let panel else { return }

        let screen = currentScreen()
        let screenFrame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY + 40

        let targetFrame = NSRect(x: x, y: y, width: panelWidth, height: 56)

        if animated {
            panel.alphaValue = 0
            panel.setFrame(targetFrame, display: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.allowsImplicitAnimation = true
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }

        panel.orderFront(nil)
    }

    private func adjustPanelWidth() {
        guard let hostingView, let panel else { return }
        let idealWidth = hostingView.intrinsicContentSize.width
        let clamped = min(max(idealWidth, 260), 660)
        let screen = currentScreen()
        let screenFrame = screen.visibleFrame
        let newOrigin = NSPoint(x: screenFrame.midX - clamped / 2, y: panel.frame.origin.y)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(NSRect(origin: newOrigin, size: NSSize(width: clamped, height: 56)), display: true)
        }
    }

    private func currentScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.screens.first
            ?? NSScreen.main
            ?? NSScreen()
    }
}
