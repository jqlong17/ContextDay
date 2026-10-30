import AppKit
import AVFoundation
import CoreGraphics

/// Layout / chrome constants for Concept A dark frosted onboarding bubble (Spec §2.7.6).
enum OnboardingBubbleLayout {
    static let bubbleWidth: CGFloat = 288
    static let bubbleHeightIntro: CGFloat = 158
    static let bubbleHeightPerms: CGFloat = 248
    static let contentPadding: CGFloat = 12
    static let gapAboveOrb: CGFloat = 8
    static let cornerRadius: CGFloat = 16
    static let tailHeight: CGFloat = 11
    static let pillHeight: CGFloat = 28
    static let nextPillWidth: CGFloat = 80
    static let grantPillWidth: CGFloat = 96
    /// Soft sage green for primary CTAs (Concept A).
    static let softGreen = NSColor(calibratedRed: 0.42, green: 0.70, blue: 0.54, alpha: 1.0)
    static let softGreenPressed = NSColor(calibratedRed: 0.34, green: 0.58, blue: 0.44, alpha: 1.0)
    /// Cream / near-white body copy on dark glass.
    static let creamText = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.90, alpha: 1.0)
    static let creamSecondary = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.90, alpha: 0.62)
}

/// Small speech-bubble panel above the desktop orb for first-run onboarding (Spec §2.7.6).
/// Streams intro copy in chunks with 「下一步」, then a short permission checklist + real TCC prompts.
/// Visual: Concept A — dark frosted glass (`NSVisualEffectView`) + soft green pill CTAs.
final class OnboardingBubbleController: NSObject {
    /// Called after the user finishes the permission step (or skips); host may re-eval ready blink.
    var onFinished: (() -> Void)?

    private var window: NSWindow?
    private var bubbleView: BubbleChromeView?
    private var bodyLabel: NSTextField!
    private var nextButton: SoftGreenPillButton!
    private var grantButton: SoftGreenPillButton!
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
        let size = NSSize(width: OnboardingBubbleLayout.bubbleWidth, height: OnboardingBubbleLayout.bubbleHeightIntro)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        // Path-shaped chrome draws its own soft shadow; OS window shadow fights the tail.
        win.hasShadow = false
        win.level = .normal
        win.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        win.isMovable = false
        win.isReleasedWhenClosed = false
        win.title = "ContextDay 引导"
        win.appearance = NSAppearance(named: .darkAqua)

        let chrome = BubbleChromeView(frame: NSRect(origin: .zero, size: size))
        chrome.autoresizingMask = [.width, .height]

        bodyLabel = NSTextField(wrappingLabelWithString: "")
        bodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        bodyLabel.textColor = OnboardingBubbleLayout.creamText
        bodyLabel.maximumNumberOfLines = 8
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.drawsBackground = false
        bodyLabel.backgroundColor = .clear
        chrome.addSubview(bodyLabel)

        nextButton = SoftGreenPillButton(title: "下一步", target: self, action: #selector(advanceIntro))
        nextButton.keyEquivalent = "\r"
        nextButton.isHidden = true
        chrome.addSubview(nextButton)

        checklistStack = NSStackView()
        checklistStack.orientation = .vertical
        checklistStack.alignment = .leading
        checklistStack.spacing = 5
        checklistStack.isHidden = true
        chrome.addSubview(checklistStack)

        for item in OnboardingFlow.permissionItems {
            let row = NSTextField(wrappingLabelWithString: "○ \(item.title) — \(item.detail)")
            row.font = .systemFont(ofSize: 12)
            row.textColor = OnboardingBubbleLayout.creamSecondary
            row.maximumNumberOfLines = 2
            row.drawsBackground = false
            row.backgroundColor = .clear
            row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            checklistStack.addArrangedSubview(row)
            checklistRows.append(row)
        }

        grantButton = SoftGreenPillButton(title: "授予权限", target: self, action: #selector(grantPermissions))
        grantButton.keyEquivalent = "\r"
        grantButton.isHidden = true
        chrome.addSubview(grantButton)

        skipButton = NSButton(title: "稍后再说", target: self, action: #selector(skipForNow))
        skipButton.isBordered = false
        skipButton.font = .systemFont(ofSize: 12, weight: .medium)
        skipButton.contentTintColor = OnboardingBubbleLayout.creamSecondary
        skipButton.isHidden = true
        chrome.addSubview(skipButton)

        win.contentView = chrome
        bubbleView = chrome
        window = win
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightIntro)
    }

    private func layoutChrome(height: CGFloat) {
        guard let chrome = bubbleView else { return }
        let w = OnboardingBubbleLayout.bubbleWidth
        let pad = OnboardingBubbleLayout.contentPadding
        let tail = OnboardingBubbleLayout.tailHeight
        let contentTop = height - pad - 2
        let contentBottom = tail + pad

        bodyLabel.frame = NSRect(
            x: pad,
            y: contentBottom + 34,
            width: w - pad * 2,
            height: contentTop - contentBottom - 40
        )
        nextButton.frame = NSRect(
            x: w - pad - OnboardingBubbleLayout.nextPillWidth,
            y: contentBottom,
            width: OnboardingBubbleLayout.nextPillWidth,
            height: OnboardingBubbleLayout.pillHeight
        )

        checklistStack.frame = NSRect(
            x: pad,
            y: contentBottom + 36,
            width: w - pad * 2,
            height: 128
        )
        grantButton.frame = NSRect(
            x: w - pad - OnboardingBubbleLayout.grantPillWidth,
            y: contentBottom,
            width: OnboardingBubbleLayout.grantPillWidth,
            height: OnboardingBubbleLayout.pillHeight
        )
        skipButton.frame = NSRect(x: pad, y: contentBottom, width: 72, height: OnboardingBubbleLayout.pillHeight)

        chrome.frame.size = NSSize(width: w, height: height)
        window?.setContentSize(NSSize(width: w, height: height))
    }

    private func reposition() {
        guard let window, let orbWindow else { return }
        let orb = orbWindow.frame
        let size = window.frame.size
        var origin = NSPoint(
            x: orb.midX - size.width / 2,
            y: orb.maxY + OnboardingBubbleLayout.gapAboveOrb
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
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightIntro)
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
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightPerms)
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
            row.textColor = flags[idx] ? OnboardingBubbleLayout.creamText : OnboardingBubbleLayout.creamSecondary
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

// MARK: - Soft green pill CTA (Concept A)

private final class SoftGreenPillButton: NSButton {
    override var title: String {
        get { super.title }
        set {
            super.title = newValue
            applyTitleStyle()
        }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = OnboardingBubbleLayout.pillHeight / 2
        layer?.backgroundColor = OnboardingBubbleLayout.softGreen.cgColor
        focusRingType = .none
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            layer?.backgroundColor = (isHighlighted
                ? OnboardingBubbleLayout.softGreenPressed
                : OnboardingBubbleLayout.softGreen).cgColor
        }
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.45
        }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    private func applyTitleStyle() {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: OnboardingBubbleLayout.creamText,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        attributedTitle = NSAttributedString(string: super.title, attributes: attrs)
    }
}

// MARK: - Bubble chrome (dark frosted glass + down-pointing tail)

private final class BubbleChromeView: NSView {
    private let effectView = NSVisualEffectView()
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        // Soft drop shadow matching Concept A depth against desktop wallpaper.
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.42
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.wantsLayer = true
        addSubview(effectView, positioned: .below, relativeTo: nil)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.22).cgColor
        borderLayer.lineWidth = 1
        borderLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        let path = Self.bubblePath(in: bounds)
        let cg = path.cgPath
        maskLayer.frame = bounds
        maskLayer.path = cg
        effectView.layer?.mask = maskLayer
        borderLayer.frame = bounds
        borderLayer.path = cg
        // Shadow path follows the bubble silhouette (including tail).
        layer?.shadowPath = cg
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only hit-test inside the bubble silhouette so transparent corners pass through.
        let path = Self.bubblePath(in: bounds)
        guard path.contains(point) else { return nil }
        return super.hitTest(point)
    }

    static func bubblePath(in bounds: NSRect) -> NSBezierPath {
        let tailH = OnboardingBubbleLayout.tailHeight
        let corner = OnboardingBubbleLayout.cornerRadius
        let card = NSRect(
            x: bounds.minX,
            y: bounds.minY + tailH,
            width: bounds.width,
            height: bounds.height - tailH
        )
        let path = NSBezierPath(roundedRect: card, xRadius: corner, yRadius: corner)
        let midX = bounds.midX
        let tip = NSPoint(x: midX, y: bounds.minY + 1)
        let left = NSPoint(x: midX - 9, y: bounds.minY + tailH + 0.5)
        let right = NSPoint(x: midX + 9, y: bounds.minY + tailH + 0.5)
        path.move(to: left)
        path.line(to: tip)
        path.line(to: right)
        path.close()
        return path
    }
}
