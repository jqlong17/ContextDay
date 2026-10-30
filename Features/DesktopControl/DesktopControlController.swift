import AppKit
import QuartzCore

/// Borderless transparent desktop orb window (Spec §2.7.2 / §2.7.3).
/// Window level sits at/below normal apps so Safari etc. can cover it — not HUD / floating.
final class DesktopControlController: NSObject, NSMenuItemValidation {
    /// Short ease-in-out for 「浮控大小」 presets — long enough to read as motion, short enough to feel snappy.
    private static let orbResizeDuration: TimeInterval = 0.28
    private var window: NSWindow?
    private var orbView: DesktopOrbView?
    private var configWindow: ConfigWindowController?
    private var timelineWindow: TimelineWindowController?
    private var aboutWindow: AboutPrivacyWindowController?
    private var onboardingBubble: OnboardingBubbleController?

    /// Wired to left-click start (idle only) / 右键「开始录音 / 暂停录音」/ 睡眠暂停.
    /// Left-click never pauses — pause/stop stays on the right-click menu (Spec §2.7.3).
    private(set) var isRecording = false
    private let capture = CapturePipeline()
    /// One-shot ready blink per cold start (Spec §2.7.4) — never spam.
    private var didPlayReadyBlink = false

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
        // 「浮控大小」 NSAnimationContext / animator().setFrame ease-in-out visible (Spec §2.7.3).
        win.animationBehavior = .documentWindow
        win.title = "ContextDay"
        win.isReleasedWhenClosed = false

        let orb = DesktopOrbView(frame: NSRect(origin: .zero, size: size))
        // Left-click (not drag): start recording when idle — guide into capture faster.
        // Already recording → no-op (pause/stop only via right-click menu). Spec §2.7.3.
        orb.onPrimaryClick = { [weak self] in
            self?.startRecordingFromPrimaryClick()
        }
        orb.onSecondaryClick = { [weak self] point in
            self?.showContextMenu(at: point)
        }
        win.contentView = orb

        window = win
        orbView = orb
        // Spec §2.7.5 / v0.3.21: cold start uses keyed idle (blink / ready path), not sleep.
        // Sleep loop is for after pause — see setRecording(false).
        orb.prefersSleepIdle = false
        orb.stopSleepIdleLoop()
        win.orderFrontRegardless()
    }

    /// Activate/stop path for left-click start / 开始录音 / 暂停录音 (and smoke).
    /// - playClip: on start, play leave-sleep feedback (wake S1 if sleeping, else eye-click).
    ///   On pause, unused — pause never plays eye-click (Spec v0.3.22); goes straight to sleep.
    private func setRecording(_ recording: Bool, playClip: Bool) {
        guard recording != isRecording else { return }
        let wasSleeping = orbView?.prefersSleepIdle == true || orbView?.isSleepLoopRunning == true
        isRecording = recording
        RuntimeHealth.shared.setUIWantsRecording(isRecording)
        if isRecording {
            // Leave sleep → wake S1 (or eye-click if already awake) → idle under clip.
            orbView?.stopSleepIdleLoop(resetUnderlayToIdle: !wasSleeping)
            capture.start()
        } else {
            capture.stop()
            // Pause → Concept A sleep immediately (no eye-click).
            orbView?.prefersSleepIdle = true
        }
        AppLog.info(.app, "ui recording → \(isRecording) pipeline=\(capture.isRunning)")
        if isRecording {
            if playClip {
                if wasSleeping {
                    orbView?.playWakeOnce()
                } else {
                    orbView?.playEyeClickOnce()
                }
            }
        } else {
            // Always straight to sleep loop; ignore playClip on pause path.
            orbView?.startSleepIdleLoop()
        }
    }

    /// Debug/smoke: --smoke-record-seconds=N
    func smokeRecord(forSeconds seconds: TimeInterval) {
        AppLog.info(.app, "smokeRecord begin \(seconds)s")
        setRecording(true, playClip: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1.0, seconds)) { [weak self] in
            AppLog.info(.app, "smokeRecord end")
            self?.setRecording(false, playClip: false)
        }
    }

    private func showContextMenu(at point: NSPoint) {
        guard let orbView else { return }

        // Spec v0.3.11: flat top-level only — no 「设置▾」 / 「调整大小」 submenu.
        let menu = NSMenu()
        menu.addItem(withTitle: "开始录音", action: #selector(startRecordingFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "暂停录音", action: #selector(pauseRecordingFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开记录文件夹", action: #selector(openRecordsFolder), keyEquivalent: "")
        menu.addItem(withTitle: "复制提示词", action: #selector(copyAgentPrompt), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "时间线…", action: #selector(openTimeline), keyEquivalent: "")
        menu.addItem(withTitle: "修改保存文件夹…", action: #selector(changeRecordsFolder), keyEquivalent: "")
        menu.addItem(withTitle: "关于与隐私…", action: #selector(openAboutPrivacy), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 ContextDay", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
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

    /// Left-click shortcut: start only when not already recording (no toggle-off).
    private func startRecordingFromPrimaryClick() {
        guard !isRecording else { return }
        setRecording(true, playClip: true)
    }

    @objc private func startRecordingFromMenu() {
        setRecording(true, playClip: true)
    }

    @objc private func pauseRecordingFromMenu() {
        setRecording(false, playClip: false)
    }

    /// Resize orb window about its center. Persistence via `OrbSizeStore` / `orbSizePt`.
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
            let wc = ConfigWindowController()
            wc.onOrbSizeChange = { [weak self] pt in
                self?.applyOrbSize(pt, animated: true)
            }
            configWindow = wc
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

    /// Spec §2.7.6: first-run speech bubble above orb while onboarding incomplete (v0.3.21).
    func considerOnboarding() {
        let gateReady = LaunchReadyGate.isReady()
        guard OnboardingFlow.shouldPresent(
            completed: OnboardingStore.isCompleted,
            gateReady: gateReady
        ) else {
            AppLog.info(
                .app,
                "onboarding skipped completed=\(OnboardingStore.isCompleted) gateReady=\(gateReady)"
            )
            return
        }
        guard let window else { return }
        if onboardingBubble == nil {
            let bubble = OnboardingBubbleController()
            bubble.onFinished = { [weak self] in
                self?.onboardingBubble = nil
                // After grants, re-check ready blink once.
                self?.considerReadyBlink()
            }
            onboardingBubble = bubble
        }
        onboardingBubble?.present(above: window)
    }

    /// Spec §2.7.4: after cold start reaches ready (mic + screen + records writable), play ready clip once.
    func considerReadyBlink() {
        guard !didPlayReadyBlink else { return }
        let gate = LaunchReadyGate.evaluate()
        guard gate.isReady else {
            AppLog.info(
                .app,
                "ready-blink deferred mic=\(gate.micAuthorized) screen=\(gate.screenAuthorized) writable=\(gate.recordsWritable)"
            )
            return
        }
        didPlayReadyBlink = true
        orbView?.playReadyOnce()
        AppLog.info(.app, "ready-blink played (cold start all-good, ready-2s)")
    }

    /// Called on system sleep / terminate — stop capture; do not auto-resume on wake.
    func handleSystemSleep() {
        guard isRecording else { return }
        setRecording(false, playClip: false)
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
