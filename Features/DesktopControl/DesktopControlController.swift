import AppKit
import QuartzCore

/// Borderless transparent desktop orb window (Spec §2.7.2 / §2.7.3).
/// Window level sits at/below normal apps so Safari etc. can cover it — not HUD / floating.
final class DesktopControlController: NSObject, NSMenuItemValidation {
    /// Short ease-in-out for 「调整大小」 presets — long enough to read as motion, short enough to feel snappy.
    private static let orbResizeDuration: TimeInterval = 0.28
    private var window: NSWindow?
    private var orbView: DesktopOrbView?
    private var configWindow: ConfigWindowController?
    private var timelineWindow: TimelineWindowController?
    private var aboutWindow: AboutPrivacyWindowController?

    /// Wired to 右键「开始录音 / 暂停录音」/ 睡眠暂停. Left-click does **not** toggle recording (Spec §2.7.3).
    private(set) var isRecording = false
    private let capture = CapturePipeline()

    func show() {
        let pt = OrbSizeStore.load()
        let size = NSSize(width: pt, height: pt)
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
        // Borderless utility-ish windows can skip frame animation; document behavior keeps
        // 「调整大小」 NSAnimationContext / animator().setFrame ease-in-out visible (Spec §2.7.3).
        win.animationBehavior = .documentWindow
        win.title = "ContextDay"
        win.isReleasedWhenClosed = false

        let orb = DesktopOrbView(frame: NSRect(origin: .zero, size: size))
        // Left-click: drag only (via isMovableByWindowBackground). Recording / eye-click
        // are right-menu (and smoke) paths — align with Notta Input: no record on primary click.
        orb.onSecondaryClick = { [weak self] point in
            self?.showContextMenu(at: point)
        }
        win.contentView = orb

        window = win
        orbView = orb
        win.orderFrontRegardless()
    }

    /// Activate/stop path for 开始录音 / 暂停录音 (and smoke). Not bound to left-click.
    private func setRecording(_ recording: Bool, playEyeClick: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        RuntimeHealth.shared.setUIWantsRecording(isRecording)
        if isRecording {
            capture.start()
        } else {
            capture.stop()
        }
        AppLog.info(.app, "ui recording → \(isRecording) pipeline=\(capture.isRunning)")
        if playEyeClick {
            orbView?.playEyeClickOnce()
        }
    }

    /// Debug/smoke: --smoke-record-seconds=N
    func smokeRecord(forSeconds seconds: TimeInterval) {
        AppLog.info(.app, "smokeRecord begin \(seconds)s")
        setRecording(true, playEyeClick: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, seconds)) { [weak self] in
            AppLog.info(.app, "smokeRecord end")
            self?.setRecording(false, playEyeClick: true)
        }
    }

    private func showContextMenu(at point: NSPoint) {
        guard let orbView else { return }

        // Top-level: Recording | Folder + prompt index | Settings submenu | Quit
        let menu = NSMenu()
        menu.addItem(withTitle: "开始录音", action: #selector(startRecordingFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "暂停录音", action: #selector(pauseRecordingFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开记录文件夹", action: #selector(openRecordsFolder), keyEquivalent: "")
        menu.addItem(withTitle: "复制提示词", action: #selector(copyAgentPrompt), keyEquivalent: "")
        menu.addItem(.separator())

        let settingsMenu = NSMenu(title: "设置")
        settingsMenu.addItem(withTitle: "偏好设置…", action: #selector(openSettings), keyEquivalent: "")
        settingsMenu.addItem(withTitle: "时间线…", action: #selector(openTimeline), keyEquivalent: "")
        settingsMenu.addItem(withTitle: "修改保存文件夹…", action: #selector(changeRecordsFolder), keyEquivalent: "")
        settingsMenu.addItem(.separator())

        let sizeMenu = NSMenu(title: "调整大小")
        for pt in OrbSizeStore.allowed {
            let title = "\(Int(pt)) pt" + (pt == OrbSizeStore.default ? "（默认）" : "")
            let item = NSMenuItem(title: title, action: #selector(changeOrbSize(_:)), keyEquivalent: "")
            item.representedObject = Double(pt)
            item.state = OrbSizeStore.load() == pt ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeRoot = NSMenuItem(title: "调整大小", action: nil, keyEquivalent: "")
        sizeRoot.submenu = sizeMenu
        settingsMenu.addItem(sizeRoot)

        settingsMenu.addItem(withTitle: "关于与隐私…", action: #selector(openAboutPrivacy), keyEquivalent: "")

        let settingsRoot = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        settingsRoot.submenu = settingsMenu
        menu.addItem(settingsRoot)

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 ContextDay", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
            if let sub = item.submenu {
                for child in sub.items {
                    child.target = self
                    if let nested = child.submenu {
                        for nestedChild in nested.items { nestedChild.target = self }
                    }
                }
            }
        }

        menu.popUp(positioning: nil, at: point, in: orbView)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(startRecordingFromMenu):
            return !isRecording
        case #selector(pauseRecordingFromMenu):
            return isRecording
        default:
            return true
        }
    }

    @objc private func startRecordingFromMenu() {
        setRecording(true, playEyeClick: true)
    }

    @objc private func pauseRecordingFromMenu() {
        setRecording(false, playEyeClick: true)
    }

    @objc private func changeOrbSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        applyOrbSize(CGFloat(value), animated: true)
    }

    /// Resize orb window about its center. Persistence unchanged (`OrbSizeStore` / `orbSizePt`).
    /// Animated path uses `NSAnimationContext` ease-in-out; contentView fills the window so
    /// `DesktopOrbView.layout` keeps idle + AVPlayer layers in sync (no settle flicker).
    private func applyOrbSize(_ pt: CGFloat, animated: Bool) {
        OrbSizeStore.save(pt)
        guard let window else { return }
        let size = NSSize(width: pt, height: pt)
        var frame = window.frame
        if abs(frame.width - size.width) < 0.5, abs(frame.height - size.height) < 0.5 {
            return
        }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = size
        frame.origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)

        guard animated else {
            window.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.orbResizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            // Animator proxy drives a smooth window frame; contentView tracks automatically.
            window.animator().setFrame(frame, display: true)
        }
    }

    @objc private func openSettings() {
        PermissionStatus.logSnapshot(reason: "settings")
        if configWindow == nil {
            configWindow = ConfigWindowController()
        }
        configWindow?.showWindow(nil)
        configWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openTimeline() {
        if timelineWindow == nil {
            timelineWindow = TimelineWindowController()
        }
        timelineWindow?.reload()
        timelineWindow?.showWindow(nil)
        timelineWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAboutPrivacy() {
        if aboutWindow == nil {
            aboutWindow = AboutPrivacyWindowController()
        }
        aboutWindow?.showWindow(nil)
        aboutWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called on system sleep / terminate — stop capture; do not auto-resume on wake.
    func handleSystemSleep() {
        guard isRecording else { return }
        setRecording(false, playEyeClick: false)
    }

    @objc private func openRecordsFolder() {
        do {
            let root = try AppPaths.ensureDirectoryTree()
            NSWorkspace.shared.open(root)
        } catch {
            AppLog.error(.app, "open records folder failed: \(error.localizedDescription)")
        }
    }

    @objc private func copyAgentPrompt() {
        do {
            try AppPaths.ensureDirectoryTree()
        } catch {
            AppLog.error(.app, "ensure dirs before copy prompt failed: \(error.localizedDescription)")
        }
        _ = AgentSkillsStore.ensureSeededFromBundle()
        // Spec §2.8: pasteboard gets a short index only — never the full proprietary brief.
        let index = AgentPromptTemplate.makeClipboardIndex(recordsRoot: AppPaths.recordsRoot)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(index, forType: .string)
        AppLog.info(.app, "clipboard index copied chars=\(index.count)")
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
                AppLog.info(.store, "records root → \(AppPaths.recordsRoot.path)")
            } catch {
                AppLog.error(.store, "prepare store after folder change failed: \(error.localizedDescription)")
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
