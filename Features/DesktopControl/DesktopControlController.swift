import AppKit

/// Borderless transparent desktop orb window (Spec §2.7.2 / §2.7.3).
/// Window level sits at/below normal apps so Safari etc. can cover it — not HUD / floating.
final class DesktopControlController: NSObject {
    private var window: NSWindow?
    private var orbView: DesktopOrbView?

    /// Phase 0 placeholder for activate ↔ stop capture. Wired to left-click; real Capture later.
    private(set) var isRecording = false
    private let capture = CapturePipeline()

    func show() {
        let size = NSSize(width: 96, height: 96)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.minY + 48
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Desktop-adjacent: above wallpaper/icons area semantics, but NOT floating/status —
        // normal app windows must be able to cover this control (Spec §2.7.2 / T16).
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        win.title = "ContextDay"
        win.isReleasedWhenClosed = false

        let orb = DesktopOrbView(frame: NSRect(origin: .zero, size: size))
        orb.onPrimaryClick = { [weak self] in
            self?.handlePrimaryClick()
        }
        orb.onSecondaryClick = { [weak self] point in
            self?.showContextMenu(at: point)
        }
        win.contentView = orb

        window = win
        orbView = orb
        win.orderFrontRegardless()
    }

    private func handlePrimaryClick() {
        isRecording.toggle()
        if isRecording {
            capture.start()
        } else {
            capture.stop()
        }
        NSLog("ContextDay: isRecording → \(isRecording) (Capture pipeline still stub)")
        orbView?.playEyeClickOnce()
    }

    private func showContextMenu(at point: NSPoint) {
        guard let orbView else { return }

        let menu = NSMenu()
        menu.addItem(withTitle: "打开记录文件夹", action: #selector(openRecordsFolder), keyEquivalent: "")
        menu.addItem(withTitle: "复制提示词", action: #selector(copyAgentPrompt), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }

        menu.popUp(positioning: nil, at: point, in: orbView)
    }

    @objc private func openRecordsFolder() {
        do {
            let root = try AppPaths.ensureDirectoryTree()
            NSWorkspace.shared.open(root)
        } catch {
            NSLog("ContextDay: open records folder failed: \(error)")
        }
    }

    @objc private func copyAgentPrompt() {
        do {
            try AppPaths.ensureDirectoryTree()
        } catch {
            NSLog("ContextDay: ensure dirs before copy prompt failed: \(error)")
        }
        let prompt = AgentPromptTemplate.makePrompt()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }
}
