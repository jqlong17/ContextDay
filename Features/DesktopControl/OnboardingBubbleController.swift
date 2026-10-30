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
    static let prevButtonWidth: CGFloat = 72
    static let grantPillWidth: CGFloat = 96
    /// Soft sage green for primary CTAs (Concept A).
    static let softGreen = NSColor(calibratedRed: 0.42, green: 0.70, blue: 0.54, alpha: 1.0)
    static let softGreenPressed = NSColor(calibratedRed: 0.34, green: 0.58, blue: 0.44, alpha: 1.0)
    /// Cream / near-white body copy on dark glass.
    static let creamText = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.90, alpha: 1.0)
    static let creamSecondary = NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.90, alpha: 0.62)
}

/// Small speech-bubble panel above the desktop orb for first-run onboarding (Spec §2.7.6).
/// Streams intro copy in chunks with 「上一步」/「下一步」, then a short permission checklist + real TCC prompts.
/// Also re-presents conversationally when required recording perms are still missing (v0.3.27).
/// Visual: Concept A — dark frosted glass (`NSVisualEffectView`) + soft green pill CTAs.
final class OnboardingBubbleController: NSObject {
    /// Called after the user finishes the permission step (or skips); host may re-eval ready blink.
    var onFinished: (() -> Void)?
    /// Fired after a start-intent grant succeeds (「那开始工作」) — host should begin capture.
    var onReadyToStartRecording: (() -> Void)?

    private var window: NSWindow?
    private var bubbleView: BubbleChromeView?
    private var bodyLabel: NSTextField!
    private var nextButton: SoftGreenPillButton!
    private var prevButton: NSButton!
    private var grantButton: SoftGreenPillButton!
    private var skipButton: NSButton!
    private var checklistStack: NSStackView!
    private var checklistRows: [NSTextField] = []

    private var segmentIndex = 0
    private var phase: Phase = .intro
    /// First-run intro vs remissible missing-permission reminder (orb / menu start).
    private var presentation: Presentation = .firstRun
    /// When true, a successful grant ends with 「那开始工作」and asks the host to start capture.
    private var startIntent = false
    private var typeTimer: Timer?
    private var dismissTimer: Timer?
    private var typedCount = 0
    private var fullSegment = ""
    private var orbWindow: NSWindow?
    private var moveObserver: NSObjectProtocol?
    /// Live follow while orb is dragged via `isMovableByWindowBackground`.
    /// AppKit's `frame` / `didMove` often lag or skip during background-drag; child-window
    /// attachment lets Window Server move the bubble with the orb. KVO + end-of-drag snap
    /// correct relative offset after release / programmatic moves (resize).
    private var frameObservation: NSKeyValueObservation?
    /// True while the primary button is down on the orb (background-drag).
    private var isOrbDragging = false
    /// Fallback poll when bubble is not a child of the orb (WS bounds → setFrame).
    private var dragFollowTimer: Timer?
    private var localMouseMonitor: Any?
    private var lastOrbOrigin: NSPoint?

    private enum Presentation {
        case firstRun
        case missingReminder
    }

    private enum Phase {
        case intro
        case permissions
        /// Short conversational ack (deferred skip / ready / still-missing lead-in).
        case conversationalAck
    }

    private enum AckKind {
        case deferredSkip
        case readyToWork
        case returnToBackground
    }

    /// Characters per tick — slightly fast so long Chinese copy does not feel sluggish.
    private static let charsPerTick = 2
    private static let tickInterval: TimeInterval = 0.028
    private static let ackHoldInterval: TimeInterval = 1.35

    /// First-run intro → permission checklist.
    func present(above orbWindow: NSWindow) {
        beginPresentation(above: orbWindow, presentation: .firstRun, startIntent: false)
        segmentIndex = 0
        phase = .intro
        showIntroChrome()
        startTyping(OnboardingFlow.introSegments[0])
        AppLog.info(.app, "onboarding bubble presented mode=firstRun")
    }

    /// Orb / menu start while recording-required permissions are still incomplete (Spec §2.7.6 v0.3.27).
    /// Login Item is never treated as blocking — `missing` should already exclude it.
    func presentMissingRequired(above orbWindow: NSWindow, missingTitles: [String]) {
        beginPresentation(above: orbWindow, presentation: .missingReminder, startIntent: true)
        showMissingReminderPhase(missingTitles: missingTitles)
        AppLog.info(
            .app,
            "onboarding bubble presented mode=missingReminder missing=\(missingTitles.joined(separator: ","))"
        )
    }

    private func beginPresentation(
        above orbWindow: NSWindow,
        presentation: Presentation,
        startIntent: Bool
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        typeTimer?.invalidate()
        typeTimer = nil
        detachFromOrbParent()
        self.orbWindow = orbWindow
        self.presentation = presentation
        self.startIntent = startIntent
        if window == nil {
            buildWindow()
        }
        reposition()
        attachAsChildOfOrb()
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: orbWindow,
            queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
        frameObservation?.invalidate()
        // `isMovableByWindowBackground` often does not post didMove on every drag tick.
        frameObservation = orbWindow.observe(\.frame, options: [.new]) { [weak self] _, _ in
            self?.reposition()
        }
        installDragTracking()
    }

    func dismiss() {
        typeTimer?.invalidate()
        typeTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        isOrbDragging = false
        stopDragFollowTimer()
        removeDragTracking()
        frameObservation?.invalidate()
        frameObservation = nil
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        detachFromOrbParent()
        window?.orderOut(nil)
        lastOrbOrigin = nil
        AppLog.info(.app, "onboarding bubble dismissed")
    }

    /// True while the bubble window is ordered in (host uses this to avoid stacking reminders).
    var isVisible: Bool {
        guard let window else { return false }
        return window.isVisible
    }

    /// Child-window attachment: Window Server moves bubble with orb during live background-drag,
    /// even when AppKit's `frame` property has not caught up yet.
    private func attachAsChildOfOrb() {
        guard let window, let orbWindow else { return }
        if window.parent !== orbWindow {
            if let existing = window.parent {
                existing.removeChildWindow(window)
            }
            orbWindow.addChildWindow(window, ordered: .above)
        }
    }

    private func detachFromOrbParent() {
        guard let window else { return }
        if let parent = window.parent {
            parent.removeChildWindow(window)
        }
    }

    private func installDragTracking() {
        removeDragTracking()
        // Local monitor: while the user drags with the primary button down, keep polling the
        // orb's on-screen frame (CGWindowList) so reposition stays glued even if KVO is quiet.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleOrbDragEvent(event)
            return event
        }
    }

    private func removeDragTracking() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        stopDragFollowTimer()
    }

    private func handleOrbDragEvent(_ event: NSEvent) {
        guard let orbWindow else { return }
        // Only track drags that belong to the orb window (background-drag path).
        guard event.window === orbWindow else {
            if event.type == .leftMouseUp, isOrbDragging {
                endOrbDrag()
            }
            return
        }
        switch event.type {
        case .leftMouseDown:
            beginOrbDrag()
        case .leftMouseDragged:
            if !isOrbDragging { beginOrbDrag() }
            // Child-attached: Window Server keeps the bubble glued — do not setFrame
            // from a possibly-stale AppKit frame (that was the #22 residual failure mode).
            if window?.parent !== orbWindow {
                reposition(force: true)
            }
        case .leftMouseUp:
            endOrbDrag()
        default:
            break
        }
    }

    private func beginOrbDrag() {
        isOrbDragging = true
        // Fallback ~60 Hz only when not child-attached.
        guard window?.parent !== orbWindow else { return }
        guard dragFollowTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.reposition(force: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        dragFollowTimer = timer
    }

    private func endOrbDrag() {
        isOrbDragging = false
        stopDragFollowTimer()
        // AppKit frame is trustworthy again after release — snap relative offset.
        reposition(force: true)
    }

    private func stopDragFollowTimer() {
        dragFollowTimer?.invalidate()
        dragFollowTimer = nil
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

        bodyLabel = Self.makeTransparentWrappingLabel()
        bodyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        bodyLabel.textColor = OnboardingBubbleLayout.creamText
        bodyLabel.maximumNumberOfLines = 8
        chrome.addSubview(bodyLabel)

        prevButton = NSButton(title: "上一步", target: self, action: #selector(goPrevious))
        prevButton.isBordered = false
        prevButton.font = .systemFont(ofSize: 12, weight: .medium)
        prevButton.contentTintColor = OnboardingBubbleLayout.creamSecondary
        prevButton.isHidden = true
        chrome.addSubview(prevButton)

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
            let row = Self.makeTransparentWrappingLabel()
            row.stringValue = "○ \(item.title) — \(item.detail)"
            row.font = .systemFont(ofSize: 12)
            row.textColor = OnboardingBubbleLayout.creamSecondary
            row.maximumNumberOfLines = 2
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

    /// Plain non-bezeled field — avoids the opaque near-black rect `wrappingLabelWithString`
    /// can paint inside a layer-backed dark frosted chrome.
    private static func makeTransparentWrappingLabel() -> NSTextField {
        let label = NSTextField(frame: .zero)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.isBordered = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.refusesFirstResponder = true
        label.allowsDefaultTighteningForTruncation = true
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        label.maximumNumberOfLines = 0
        if let cell = label.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.isScrollable = false
            cell.drawsBackground = false
            cell.backgroundColor = .clear
        }
        return label
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
        prevButton.frame = NSRect(
            x: pad,
            y: contentBottom,
            width: OnboardingBubbleLayout.prevButtonWidth,
            height: OnboardingBubbleLayout.pillHeight
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
        // Permissions row: 「上一步」 + 「稍后再说」 on the left, 「授予权限」 on the right.
        skipButton.frame = NSRect(
            x: pad + OnboardingBubbleLayout.prevButtonWidth + 4,
            y: contentBottom,
            width: 72,
            height: OnboardingBubbleLayout.pillHeight
        )

        chrome.frame.size = NSSize(width: w, height: height)
        window?.setContentSize(NSSize(width: w, height: height))
    }

    private func reposition(force: Bool = false) {
        guard let window, let orbWindow else { return }
        // Mid-drag with child attachment: Window Server already keeps the relative offset.
        // Writing setFrame from a possibly-stale AppKit `frame` would yank the bubble back.
        if !force, isOrbDragging, window.parent === orbWindow {
            return
        }
        let orb = liveOrbFrame(for: orbWindow)
        let size = window.frame.size
        var origin = NSPoint(
            x: orb.midX - size.width / 2,
            y: orb.maxY + OnboardingBubbleLayout.gapAboveOrb
        )
        if let screen = orbWindow.screen ?? screenContaining(orb) ?? NSScreen.main {
            let vis = screen.visibleFrame
            origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - size.width - 8)
            if origin.y + size.height > vis.maxY - 8 {
                // Prefer above; if clipped, sit just under the top edge.
                origin.y = max(vis.minY + 8, vis.maxY - size.height - 8)
            }
        }
        // Skip no-op writes so child-window WS coupling is not fought every tick.
        if !force,
           let last = lastOrbOrigin,
           abs(last.x - orb.origin.x) < 0.5,
           abs(last.y - orb.origin.y) < 0.5,
           abs(window.frame.origin.x - origin.x) < 0.5,
           abs(window.frame.origin.y - origin.y) < 0.5 {
            return
        }
        lastOrbOrigin = orb.origin
        // Origin-only update avoids resize flicker while following a live drag.
        window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    /// Prefer Window Server bounds during live drag — AppKit `frame` can lag behind
    /// `isMovableByWindowBackground` motion. Used when child attachment is unavailable.
    private func liveOrbFrame(for orbWindow: NSWindow) -> NSRect {
        let appKit = orbWindow.frame
        let windowID = CGWindowID(orbWindow.windowNumber)
        guard windowID != 0,
              let infoList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = infoList.first,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let cgRect = CGRect(dictionaryRepresentation: boundsDict)
        else {
            return appKit
        }
        // Quartz global (top-left of main display, Y down) → AppKit (bottom-left, Y up).
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        guard let primary else { return appKit }
        let converted = NSRect(
            x: cgRect.origin.x,
            y: primary.frame.maxY - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
        // Sanity: size must match; if conversion is nonsense, keep AppKit.
        if abs(converted.width - appKit.width) > 2 || abs(converted.height - appKit.height) > 2 {
            return appKit
        }
        return converted
    }

    private func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    // MARK: - Intro typing

    private func showIntroChrome() {
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightIntro)
        checklistStack.isHidden = true
        grantButton.isHidden = true
        skipButton.isHidden = true
        nextButton.isHidden = true
        nextButton.title = segmentIndex + 1 < OnboardingFlow.introCount ? "下一步" : "了解权限"
        updatePrevButtonVisibility(typing: true)
        bodyLabel.isHidden = false
        reposition()
    }

    private func updatePrevButtonVisibility(typing: Bool) {
        switch phase {
        case .intro:
            // Hidden on page 0; shown once the user can go back (and after typing finishes).
            let canGoBack = segmentIndex > 0
            prevButton.isHidden = !canGoBack || typing
            prevButton.isEnabled = canGoBack
        case .permissions:
            // Reminder mode has no intro to step back into.
            let showPrev = presentation == .firstRun
            prevButton.isHidden = !showPrev
            prevButton.isEnabled = showPrev
        case .conversationalAck:
            prevButton.isHidden = true
            prevButton.isEnabled = false
        }
    }

    private func startTyping(_ text: String) {
        typeTimer?.invalidate()
        fullSegment = text
        typedCount = 0
        bodyLabel.stringValue = ""
        nextButton.isHidden = true
        updatePrevButtonVisibility(typing: true)
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
            switch phase {
            case .conversationalAck:
                // Soft-close is driven by dismissTimer started in showConversationalAck.
                nextButton.isHidden = true
                updatePrevButtonVisibility(typing: false)
            case .intro, .permissions:
                nextButton.isHidden = false
                updatePrevButtonVisibility(typing: false)
            }
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
            updatePrevButtonVisibility(typing: false)
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

    @objc private func goPrevious() {
        typeTimer?.invalidate()
        typeTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        switch phase {
        case .permissions:
            guard presentation == .firstRun else { return }
            // Return to the last intro segment (fully shown — no re-type).
            phase = .intro
            segmentIndex = max(0, OnboardingFlow.introCount - 1)
            showIntroChrome()
            fullSegment = OnboardingFlow.introSegments[segmentIndex]
            typedCount = fullSegment.count
            bodyLabel.stringValue = fullSegment
            nextButton.isHidden = false
            updatePrevButtonVisibility(typing: false)
        case .intro:
            guard segmentIndex > 0 else { return }
            segmentIndex -= 1
            showIntroChrome()
            fullSegment = OnboardingFlow.introSegments[segmentIndex]
            typedCount = fullSegment.count
            bodyLabel.stringValue = fullSegment
            nextButton.isHidden = false
            nextButton.title = segmentIndex + 1 < OnboardingFlow.introCount ? "下一步" : "了解权限"
            updatePrevButtonVisibility(typing: false)
        case .conversationalAck:
            break
        }
    }

    // MARK: - Permissions

    private func showPermissionsPhase() {
        phase = .permissions
        typeTimer?.invalidate()
        typeTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightPerms)
        bodyLabel.stringValue = OnboardingFlow.permissionsIntroBody
        bodyLabel.isHidden = false
        nextButton.isHidden = true
        checklistStack.isHidden = false
        grantButton.isHidden = false
        skipButton.isHidden = false
        grantButton.isEnabled = true
        skipButton.isEnabled = true
        updatePrevButtonVisibility(typing: false)
        refreshChecklistMarks()
        reposition()
    }

    private func showMissingReminderPhase(missingTitles: [String]) {
        phase = .permissions
        typeTimer?.invalidate()
        typeTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightPerms)
        bodyLabel.stringValue = OnboardingFlow.missingRequiredMessage(missingTitles: missingTitles)
        bodyLabel.isHidden = false
        nextButton.isHidden = true
        checklistStack.isHidden = false
        grantButton.isHidden = false
        skipButton.isHidden = false
        grantButton.isEnabled = true
        skipButton.isEnabled = true
        updatePrevButtonVisibility(typing: false)
        refreshChecklistMarks()
        reposition()
    }

    private func currentPermissionFlags() -> OnboardingFlow.PermissionFlags {
        let snap = PermissionStatus.snapshot()
        let loginOK = LoginItemService.status == .enabled || LoginItemService.status == .requiresApproval
        return OnboardingFlow.PermissionFlags(
            loginItemOK: loginOK,
            microphoneOK: snap.entry(.microphone)?.state == .authorized,
            screenRecordingOK: snap.entry(.screenRecording)?.state == .authorized,
            recordsFolderOK: LaunchReadyGate.isWritableDirectory(AppPaths.recordsRoot)
        )
    }

    private func refreshChecklistMarks() {
        let flags = currentPermissionFlags()
        for (idx, row) in checklistRows.enumerated() {
            guard OnboardingFlow.permissionItems.indices.contains(idx) else { continue }
            let item = OnboardingFlow.permissionItems[idx]
            let ok = flags.isSatisfied(itemID: item.id)
            let mark = ok ? "●" : "○"
            let suffix: String
            switch item.requirement {
            case .informational:
                suffix = ok ? item.detail : "\(item.detail)（不影响开录）"
            case .recordingRequired:
                suffix = item.detail
            }
            row.stringValue = "\(mark) \(item.title) — \(suffix)"
            row.textColor = ok ? OnboardingBubbleLayout.creamText : OnboardingBubbleLayout.creamSecondary
        }
    }

    @objc private func grantPermissions() {
        grantButton.isEnabled = false
        skipButton.isEnabled = false
        prevButton.isEnabled = false
        AppLog.info(.app, "onboarding grantPermissions tapped startIntent=\(startIntent)")

        // 1) Login Item preference ON + register (informational — never blocks start).
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
                self.prevButton.isEnabled = self.presentation == .firstRun
                self.handlePostGrantOutcome()
            }
        }
    }

    private func handlePostGrantOutcome() {
        let flags = currentPermissionFlags()
        let missing = OnboardingFlow.missingRecordingRequired(flags: flags)
        if missing.isEmpty {
            let kind: AckKind = startIntent ? .readyToWork : .returnToBackground
            showConversationalAck(kind)
            return
        }
        // Still missing required — stay open so the user can grant again; login item ignored.
        bodyLabel.stringValue = OnboardingFlow.missingRequiredMessage(
            missingTitles: missing.map(\.title)
        )
        phase = .permissions
        checklistStack.isHidden = false
        grantButton.isHidden = false
        skipButton.isHidden = false
        nextButton.isHidden = true
        updatePrevButtonVisibility(typing: false)
        AppLog.info(
            .app,
            "onboarding grant incomplete missing=\(missing.map(\.id).joined(separator: ","))"
        )
    }

    @objc private func skipForNow() {
        // Mark completed so we do not re-spam the intro every cold start;
        // conversational deferral, then soft-close — never start capture.
        OnboardingStore.markCompleted()
        AppLog.info(.app, "onboarding skipped (deferred ack)")
        showConversationalAck(.deferredSkip)
    }

    private func showConversationalAck(_ kind: AckKind) {
        phase = .conversationalAck
        typeTimer?.invalidate()
        typeTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        layoutChrome(height: OnboardingBubbleLayout.bubbleHeightIntro)
        checklistStack.isHidden = true
        grantButton.isHidden = true
        skipButton.isHidden = true
        nextButton.isHidden = true
        prevButton.isHidden = true
        bodyLabel.isHidden = false
        let text: String
        switch kind {
        case .deferredSkip:
            text = OnboardingFlow.deferredSkipMessage
        case .readyToWork:
            text = OnboardingFlow.readyToWorkMessage
        case .returnToBackground:
            text = OnboardingFlow.returnToBackgroundMessage
        }
        startTyping(text)
        // Soft-close after typing duration + brief hold; do not start capture on deferred.
        let typeSeconds = ceil(Double(text.count) / Double(Self.charsPerTick)) * Self.tickInterval
        let delay = typeSeconds + Self.ackHoldInterval
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            switch kind {
            case .deferredSkip, .returnToBackground:
                self.finish(startRecording: false)
            case .readyToWork:
                self.finish(startRecording: true)
            }
        }
        if let dismissTimer {
            RunLoop.main.add(dismissTimer, forMode: .common)
        }
        reposition()
    }

    private func finish(startRecording: Bool) {
        dismiss()
        if startRecording {
            onReadyToStartRecording?()
        }
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
