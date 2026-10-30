import AppKit
import AVFoundation
import CoreGraphics

/// Small speech-bubble panel above the desktop orb for first-run onboarding (Spec §2.7.6).
/// Streams intro copy in chunks with 「下一步」, then a short permission checklist + real TCC prompts.
final class OnboardingBubbleController: NSObject {
    /// Called after the user finishes the permission step (or skips); host may re-eval ready blink.
    var onFinished: (() -> Void)?

    private var window: NSWindow?
    private var bubbleView: BubbleChromeView?
    private var bodyLabel: NSTextField!
    private var nextButton: NSButton!
    private var grantButton: NSButton!
    private var skipButton: NSButton!
    private var checklistStack: NSStackView!
    private var checklistRows: [NSTextField] = []

    private var segmentIndex = 0
    private var phase: Phase = .intro
    private var typeTimer: Timer?
    private var typedCount = 0
    private var fullSegment = ""
    private var orbWindow: NSWindow?
    private var moveObserver: NSObjectProtocol?

    private enum Phase {
        case intro
        case permissions
    }

    /// Characters per tick — slightly fast so long Chinese copy does not feel sluggish.
    private static let charsPerTick = 2
    private static let tickInterval: TimeInterval = 0.028
    private static let bubbleWidth: CGFloat = 312
    private static let bubbleHeightIntro: CGFloat = 196
    private static let bubbleHeightPerms: CGFloat = 268
    private static let gapAboveOrb: CGFloat = 10

    func present(above orbWindow: NSWindow) {
        self.orbWindow = orbWindow
        if window == nil {
            buildWindow()
        }
        segmentIndex = 0
        phase = .intro
        showIntroChrome()
        startTyping(OnboardingFlow.introSegments[0])
        reposition()
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: orbWindow,
            queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
        AppLog.info(.app, "onboarding bubble presented")
    }

    func dismiss() {
        typeTimer?.invalidate()
        typeTimer = nil
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        window?.orderOut(nil)
        AppLog.info(.app, "onboarding bubble dismissed")
    }

    // MARK: - Layout

    private func buildWindow() {
        let size = NSSize(width: Self.bubbleWidth, height: Self.bubbleHeightIntro)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .normal
        win.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        win.isMovable = false
        win.isReleasedWhenClosed = false
        win.title = "ContextDay 引导"

        let chrome = BubbleChromeView(frame: NSRect(origin: .zero, size: size))
        chrome.autoresizingMask = [.width, .height]

        bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .labelColor
        bodyLabel.maximumNumberOfLines = 8
        bodyLabel.lineBreakMode = .byWordWrapping
        chrome.addSubview(bodyLabel)

        nextButton = NSButton(title: "下一步", target: self, action: #selector(advanceIntro))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.isHidden = true
        chrome.addSubview(nextButton)

        checklistStack = NSStackView()
        checklistStack.orientation = .vertical
        checklistStack.alignment = .leading
        checklistStack.spacing = 6
        checklistStack.isHidden = true
        chrome.addSubview(checklistStack)

        for item in OnboardingFlow.permissionItems {
            let row = NSTextField(wrappingLabelWithString: "○ \(item.title) — \(item.detail)")
            row.font = .systemFont(ofSize: 12)
            row.textColor = .secondaryLabelColor
            row.maximumNumberOfLines = 2
            row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            checklistStack.addArrangedSubview(row)
            checklistRows.append(row)
        }

        grantButton = NSButton(title: "授予权限", target: self, action: #selector(grantPermissions))
        grantButton.bezelStyle = .rounded
        grantButton.keyEquivalent = "\r"
        grantButton.isHidden = true
        chrome.addSubview(grantButton)

        skipButton = NSButton(title: "稍后再说", target: self, action: #selector(skipForNow))
        skipButton.bezelStyle = .recessed
        skipButton.isHidden = true
        chrome.addSubview(skipButton)

        win.contentView = chrome
        bubbleView = chrome
        window = win
        layoutChrome(height: Self.bubbleHeightIntro)
    }

    private func layoutChrome(height: CGFloat) {
        guard let chrome = bubbleView else { return }
        let w = Self.bubbleWidth
        let pad: CGFloat = 16
        let tail: CGFloat = BubbleChromeView.tailHeight
        let contentTop = height - pad - 4
        let contentBottom = tail + pad

        bodyLabel.frame = NSRect(
            x: pad,
            y: contentBottom + 36,
            width: w - pad * 2,
            height: contentTop - contentBottom - 44
        )
        nextButton.frame = NSRect(x: w - pad - 88, y: contentBottom, width: 88, height: 28)

        checklistStack.frame = NSRect(
            x: pad,
            y: contentBottom + 40,
            width: w - pad * 2,
            height: 140
        )
        grantButton.frame = NSRect(x: w - pad - 100, y: contentBottom, width: 100, height: 28)
        skipButton.frame = NSRect(x: pad, y: contentBottom, width: 88, height: 28)

        chrome.frame.size = NSSize(width: w, height: height)
        window?.setContentSize(NSSize(width: w, height: height))
    }

    private func reposition() {
        guard let window, let orbWindow else { return }
        let orb = orbWindow.frame
        let size = window.frame.size
        var origin = NSPoint(
            x: orb.midX - size.width / 2,
            y: orb.maxY + Self.gapAboveOrb
        )
        if let screen = orbWindow.screen ?? NSScreen.main {
            let vis = screen.visibleFrame
            origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - size.width - 8)
            if origin.y + size.height > vis.maxY - 8 {
                // Prefer above; if clipped, sit just under the top edge.
                origin.y = max(vis.minY + 8, vis.maxY - size.height - 8)
            }
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Intro typing

    private func showIntroChrome() {
        layoutChrome(height: Self.bubbleHeightIntro)
        checklistStack.isHidden = true
        grantButton.isHidden = true
        skipButton.isHidden = true
        nextButton.isHidden = true
        nextButton.title = segmentIndex + 1 < OnboardingFlow.introCount ? "下一步" : "了解权限"
        bodyLabel.isHidden = false
        reposition()
    }

    private func startTyping(_ text: String) {
        typeTimer?.invalidate()
        fullSegment = text
        typedCount = 0
        bodyLabel.stringValue = ""
        nextButton.isHidden = true
        typeTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.typeTick()
        }
        if let typeTimer {
            RunLoop.main.add(typeTimer, forMode: .common)
        }
    }

    private func typeTick() {
        let chars = Array(fullSegment)
        if typedCount >= chars.count {
            typeTimer?.invalidate()
            typeTimer = nil
            nextButton.isHidden = false
            return
        }
        let end = min(typedCount + Self.charsPerTick, chars.count)
        typedCount = end
        bodyLabel.stringValue = String(chars[0..<end])
    }

    @objc private func advanceIntro() {
        if typedCount < fullSegment.count {
            // Skip remaining typing on click.
            typeTimer?.invalidate()
            typeTimer = nil
            bodyLabel.stringValue = fullSegment
            typedCount = fullSegment.count
            nextButton.isHidden = false
            return
        }
        let next = segmentIndex + 1
        if next < OnboardingFlow.introCount {
            segmentIndex = next
            showIntroChrome()
            startTyping(OnboardingFlow.introSegments[segmentIndex])
        } else {
            showPermissionsPhase()
        }
    }

    // MARK: - Permissions

    private func showPermissionsPhase() {
        phase = .permissions
        typeTimer?.invalidate()
        typeTimer = nil
        layoutChrome(height: Self.bubbleHeightPerms)
        bodyLabel.stringValue = "为了做到这件事，需要你授予下面几项权限。点「授予权限」后会依次弹出系统对话框："
        bodyLabel.isHidden = false
        nextButton.isHidden = true
        checklistStack.isHidden = false
        grantButton.isHidden = false
        skipButton.isHidden = false
        refreshChecklistMarks()
        reposition()
    }

    private func refreshChecklistMarks() {
        let snap = PermissionStatus.snapshot()
        let micOK = snap.entry(.microphone)?.state == .authorized
        let screenOK = snap.entry(.screenRecording)?.state == .authorized
        let folderOK = LaunchReadyGate.isWritableDirectory(AppPaths.recordsRoot)
        let loginOK = LoginItemService.status == .enabled || LoginItemService.status == .requiresApproval

        let flags = [loginOK, micOK, screenOK, folderOK]
        for (idx, row) in checklistRows.enumerated() {
            guard OnboardingFlow.permissionItems.indices.contains(idx) else { continue }
            let item = OnboardingFlow.permissionItems[idx]
            let mark = flags[idx] ? "●" : "○"
            row.stringValue = "\(mark) \(item.title) — \(item.detail)"
            row.textColor = flags[idx] ? .labelColor : .secondaryLabelColor
        }
    }

    @objc private func grantPermissions() {
        grantButton.isEnabled = false
        skipButton.isEnabled = false
        AppLog.info(.app, "onboarding grantPermissions tapped")

        // 1) Login Item preference ON + register.
        var cfg = AppConfigStore.load()
        cfg.openAtLogin = true
        AppConfigStore.save(cfg)
        LoginItemService.syncFromPreference(true)
        refreshChecklistMarks()

        // 2) Microphone TCC prompt.
        requestMic { [weak self] in
            guard let self else { return }
            self.refreshChecklistMarks()
            // 3) Screen Recording (system audio via SCK).
            _ = CGRequestScreenCaptureAccess()
            self.refreshChecklistMarks()
            // 4) Ensure records root writable; if not, open folder picker.
            self.ensureRecordsWritable { [weak self] in
                guard let self else { return }
                self.refreshChecklistMarks()
                OnboardingStore.markCompleted()
                PermissionStatus.logSnapshot(reason: "onboarding_complete")
                self.grantButton.isEnabled = true
                self.skipButton.isEnabled = true
                self.finish()
            }
        }
    }

    @objc private func skipForNow() {
        // Still mark completed so we do not re-spam the intro every cold start;
        // user can grant later via Settings / first record.
        OnboardingStore.markCompleted()
        AppLog.info(.app, "onboarding skipped")
        finish()
    }

    private func finish() {
        dismiss()
        onFinished?()
    }

    private func requestMic(completion: @escaping () -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { _ in
                DispatchQueue.main.async { completion() }
            }
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion() }
            }
        }
    }

    private func ensureRecordsWritable(completion: @escaping () -> Void) {
        if LaunchReadyGate.isWritableDirectory(AppPaths.recordsRoot) {
            do { try AppPaths.ensureDirectoryTree() } catch {
                AppLog.error(.store, "onboarding ensure dirs: \(error.localizedDescription)")
            }
            completion()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择 ContextDay 记录保存文件夹（需可写）"
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                AppPaths.setRecordsRoot(url)
                do {
                    try SegmentStore.shared.prepareApplicationSupport()
                } catch {
                    AppLog.error(.store, "onboarding prepare store: \(error.localizedDescription)")
                }
            }
            self?.refreshChecklistMarks()
            completion()
        }
    }
}

// MARK: - Bubble chrome (rounded card + down-pointing tail)

private final class BubbleChromeView: NSView {
    static let tailHeight: CGFloat = 12
    static let corner: CGFloat = 14

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let tailH = Self.tailHeight
        let body = bounds.insetBy(dx: 0, dy: 0)
        let card = NSRect(
            x: body.minX,
            y: body.minY + tailH,
            width: body.width,
            height: body.height - tailH
        )
        let path = NSBezierPath(roundedRect: card, xRadius: Self.corner, yRadius: Self.corner)
        let midX = body.midX
        let tip = NSPoint(x: midX, y: body.minY + 1)
        let left = NSPoint(x: midX - 10, y: body.minY + tailH + 1)
        let right = NSPoint(x: midX + 10, y: body.minY + tailH + 1)
        path.move(to: left)
        path.line(to: tip)
        path.line(to: right)
        path.close()

        NSColor.controlBackgroundColor.withAlphaComponent(0.96).setFill()
        path.fill()

        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
