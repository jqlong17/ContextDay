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
        // Spec §2.7.2 / T16: must be coverable by Safari/Chrome etc. — use `.normal`, not
        // `.floating` / status. Do NOT use `CGWindowLevelForKey(.desktopIconWindow)`: that
        // sits under Finder desktop icons and the orb becomes invisible in normal bring-up.
        win.level = .normal
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
        menu.addItem(withTitle: "修改保存文件夹…", action: #selector(changeRecordsFolder), keyEquivalent: "")
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
        let prompt = AgentPromptTemplate.makePrompt(recordsRoot: AppPaths.recordsRoot)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    @objc private func changeRecordsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择 ContextDay 记录保存文件夹（将在其下创建 db/、audio/ 等）"
        panel.directoryURL = AppPaths.recordsRoot.deletingLastPathComponent()

        let applySelection: (URL) -> Void = { url in
            AppPaths.setRecordsRoot(url)
            do {
                try SegmentStore.shared.prepareApplicationSupport()
                NSLog("ContextDay: records root → \(AppPaths.recordsRoot.path)")
            } catch {
                NSLog("ContextDay: prepare store after folder change failed: \(error)")
            }
        }

        if let window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                applySelection(url)
            }
        } else {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            applySelection(url)
        }
    }
}
