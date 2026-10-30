import AppKit

/// Single settings panel (Spec §2.7.3 / v0.3.11): prefs + orb size; no nested menus.
final class ConfigWindowController: NSWindowController {
    /// Fired when user picks a new orb size (pt). Host applies animated resize.
    var onOrbSizeChange: ((CGFloat) -> Void)?

    private var gateButton: NSButton!
    private var keepAudioButton: NSButton!
    private var scopePopup: NSPopUpButton!
    private var qualityPopup: NSPopUpButton!
    private var retentionField: NSTextField!
    private var systemAudioButton: NSButton!
    private var openAtLoginButton: NSButton!
    private var orbSizePopup: NSPopUpButton!
    private var estimateLabel: NSTextField!
    private var promptViewer: PromptViewerSheetController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ContextDay 设置"
        window.center()
        self.init(window: window)
        buildUI()
        loadFromStore()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let documentHeight: CGFloat = 520
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: documentHeight))
        var y = documentHeight - 36

        func placeCheckbox(_ title: String) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed))
            b.frame = NSRect(x: 24, y: y, width: 380, height: 24)
            doc.addSubview(b)
            y -= 34
            return b
        }

        func placeLabeledPopup(label: String, width: CGFloat) -> NSPopUpButton {
            let l = NSTextField(labelWithString: label)
            l.frame = NSRect(x: 24, y: y, width: 100, height: 24)
            doc.addSubview(l)
            let p = NSPopUpButton(frame: NSRect(x: 130, y: y - 1, width: width, height: 26))
            p.target = self
            p.action = #selector(changed)
            doc.addSubview(p)
            y -= 36
            return p
        }

        gateButton = placeCheckbox("分类过滤（YAMNet）")
        keepAudioButton = placeCheckbox("保留音频（证据回听）")

        scopePopup = placeLabeledPopup(label: "音频范围", width: 200)
        scopePopup.removeAllItems()
        scopePopup.addItems(withTitles: ["仅人声", "全部"])

        qualityPopup = placeLabeledPopup(label: "音频质量", width: 200)
        qualityPopup.removeAllItems()
        qualityPopup.addItems(withTitles: ["Opus 12 kbps", "Opus 24 kbps（默认）", "Opus 64 kbps"])

        let rLabel = NSTextField(labelWithString: "保留天数")
        rLabel.frame = NSRect(x: 24, y: y, width: 100, height: 24)
        doc.addSubview(rLabel)
        retentionField = NSTextField(frame: NSRect(x: 130, y: y, width: 80, height: 24))
        retentionField.placeholderString = "30 / 空=不自动删"
        retentionField.target = self
        retentionField.action = #selector(changed)
        doc.addSubview(retentionField)
        y -= 36

        systemAudioButton = placeCheckbox("采集系统声（ScreenCaptureKit）")
        openAtLoginButton = placeCheckbox("登录时打开（Login Item）")

        orbSizePopup = placeLabeledPopup(label: "浮控大小", width: 200)
        orbSizePopup.removeAllItems()
        for pt in OrbSizeStore.allowed {
            let title = "\(Int(pt)) pt" + (pt == OrbSizeStore.default ? "（默认）" : "")
            orbSizePopup.addItem(withTitle: title)
        }
        orbSizePopup.target = self
        orbSizePopup.action = #selector(orbSizeChanged)

        estimateLabel = NSTextField(labelWithString: "")
        estimateLabel.frame = NSRect(x: 24, y: y - 20, width: 390, height: 44)
        estimateLabel.maximumNumberOfLines = 2
        doc.addSubview(estimateLabel)
        y -= 56

        let viewPrompt = NSButton(
            title: "查看完整提示词…",
            target: self,
            action: #selector(showFullPrompt)
        )
        viewPrompt.frame = NSRect(x: 24, y: y, width: 160, height: 28)
        doc.addSubview(viewPrompt)

        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 320, y: y, width: 90, height: 28)
        doc.addSubview(save)

        scroll.documentView = doc
        content.addSubview(scroll)
        // After layout, scroll to top.
        DispatchQueue.main.async {
            if let docView = scroll.documentView {
                docView.scroll(NSPoint(x: 0, y: docView.bounds.maxY))
            }
        }
    }

    private func loadFromStore() {
        let cfg = AppConfigStore.load()
        gateButton.state = cfg.gateEnabled ? .on : .off
        keepAudioButton.state = cfg.keepAudio ? .on : .off
        scopePopup.selectItem(at: cfg.audioScope == .speechOnly ? 0 : 1)
        switch cfg.audioQuality {
        case .opus12: qualityPopup.selectItem(at: 0)
        case .opus24: qualityPopup.selectItem(at: 1)
        case .opus64: qualityPopup.selectItem(at: 2)
        }
        if let days = cfg.retentionDays {
            retentionField.stringValue = "\(days)"
        } else {
            retentionField.stringValue = ""
        }
        systemAudioButton.state = cfg.captureSystemAudio ? .on : .off
        openAtLoginButton.state = cfg.openAtLogin ? .on : .off

        let currentPt = OrbSizeStore.load()
        if let idx = OrbSizeStore.allowed.firstIndex(of: currentPt) {
            orbSizePopup.selectItem(at: idx)
        } else {
            orbSizePopup.selectItem(at: OrbSizeStore.allowed.firstIndex(of: OrbSizeStore.default) ?? 1)
        }
        refreshEstimate()
    }

    @objc private func changed() { refreshEstimate() }

    @objc private func orbSizeChanged() {
        let idx = orbSizePopup.indexOfSelectedItem
        guard idx >= 0, idx < OrbSizeStore.allowed.count else { return }
        let pt = OrbSizeStore.allowed[idx]
        onOrbSizeChange?(pt)
    }

    private func refreshEstimate() {
        let gateOn = gateButton.state == .on
        // Spec T11: gate off → scope forced to「全部」, speech-only disabled.
        scopePopup.isEnabled = gateOn
        if !gateOn {
            scopePopup.selectItem(at: 1)
        }
        qualityPopup.isEnabled = keepAudioButton.state == .on
        scopePopup.isEnabled = gateOn && keepAudioButton.state == .on

        let cfg = currentConfig()
        estimateLabel.stringValue = cfg.keepAudio
            ? String(format: "开留音时约 %.2f GB/天（全天粗算，未计门控折扣）", cfg.estimatedKeepAudioGBPerDay)
            : "留音默认关；开启后按 Opus 档估算占用。"
    }

    private func currentConfig() -> AppConfig {
        var cfg = AppConfigStore.load()
        cfg.gateEnabled = gateButton.state == .on
        cfg.keepAudio = keepAudioButton.state == .on
        cfg.audioScope = scopePopup.indexOfSelectedItem == 0 ? .speechOnly : .all
        switch qualityPopup.indexOfSelectedItem {
        case 0: cfg.audioQuality = .opus12
        case 2: cfg.audioQuality = .opus64
        default: cfg.audioQuality = .opus24
        }
        let trimmed = retentionField.stringValue.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            cfg.retentionDays = nil
        } else {
            cfg.retentionDays = Int(trimmed) ?? 30
        }
        cfg.captureSystemAudio = systemAudioButton.state == .on
        cfg.openAtLogin = openAtLoginButton.state == .on
        cfg.normalize()
        return cfg
    }

    @objc private func showFullPrompt() {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        let text = AgentPromptTemplate.makeFullPrompt(recordsRoot: AppPaths.recordsRoot)
        let viewer = PromptViewerSheetController(text: text)
        promptViewer = viewer
        guard let sheet = viewer.window, let parent = window else { return }
        parent.beginSheet(sheet) { [weak self] _ in
            self?.promptViewer = nil
        }
        AppLog.info(.app, "full prompt viewer opened chars=\(text.count)")
    }

    @objc private func save() {
        let cfg = currentConfig()
        AppConfigStore.save(cfg)
        LoginItemService.syncFromPreference(cfg.openAtLogin)
        // Persist size even if user only hit Save without changing popup again.
        let idx = orbSizePopup.indexOfSelectedItem
        if idx >= 0, idx < OrbSizeStore.allowed.count {
            let pt = OrbSizeStore.allowed[idx]
            OrbSizeStore.save(pt)
            onOrbSizeChange?(pt)
        }
        window?.close()
    }
}
