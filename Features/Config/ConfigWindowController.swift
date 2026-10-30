import AppKit

/// Single settings panel (Spec §2.7.3 / v0.3.11): prefs + orb size + UK skill shelf; no nested menus.
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
    private var skillPopup: NSPopUpButton!
    private var skillPreviewView: NSTextView!
    private var skillCopyStatus: NSTextField!
    private var ukSkills: [AgentSkillsStore.SkillMeta] = []
    private var promptViewer: PromptViewerSheetController?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
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

        let documentHeight: CGFloat = 760
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: documentHeight))
        var y = documentHeight - 36

        func placeCheckbox(_ title: String) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed))
            b.frame = NSRect(x: 24, y: y, width: 400, height: 24)
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
        estimateLabel.frame = NSRect(x: 24, y: y - 20, width: 410, height: 44)
        estimateLabel.maximumNumberOfLines = 2
        doc.addSubview(estimateLabel)
        y -= 56

        // MARK: UK meeting skill shelf (flat section — no nested menu)
        let shelfHeader = NSTextField(labelWithString: "UK meeting skill shelf")
        shelfHeader.font = .boldSystemFont(ofSize: 13)
        shelfHeader.frame = NSRect(x: 24, y: y, width: 400, height: 22)
        doc.addSubview(shelfHeader)
        y -= 26

        let shelfHint = NSTextField(labelWithString: "浏览样式 → 预览示例 → 复制一行「请阅读 …」给 Grok Bot。导出通道稍后自选；默认不自动发邮件。")
        shelfHint.font = .systemFont(ofSize: 11)
        shelfHint.textColor = .secondaryLabelColor
        shelfHint.maximumNumberOfLines = 2
        shelfHint.frame = NSRect(x: 24, y: y - 14, width: 410, height: 36)
        doc.addSubview(shelfHint)
        y -= 48

        let skillLabel = NSTextField(labelWithString: "样式")
        skillLabel.frame = NSRect(x: 24, y: y, width: 100, height: 24)
        doc.addSubview(skillLabel)
        skillPopup = NSPopUpButton(frame: NSRect(x: 130, y: y - 1, width: 290, height: 26))
        skillPopup.target = self
        skillPopup.action = #selector(skillSelectionChanged)
        doc.addSubview(skillPopup)
        y -= 36

        let previewLabel = NSTextField(labelWithString: "示例预览")
        previewLabel.frame = NSRect(x: 24, y: y, width: 120, height: 20)
        previewLabel.font = .systemFont(ofSize: 11)
        previewLabel.textColor = .secondaryLabelColor
        doc.addSubview(previewLabel)
        y -= 24

        let previewScroll = NSScrollView(frame: NSRect(x: 24, y: y - 120, width: 400, height: 128))
        previewScroll.hasVerticalScroller = true
        previewScroll.hasHorizontalScroller = false
        previewScroll.borderType = .bezelBorder
        previewScroll.autohidesScrollers = true
        skillPreviewView = NSTextView(frame: NSRect(x: 0, y: 0, width: 382, height: 128))
        skillPreviewView.isEditable = false
        skillPreviewView.isSelectable = true
        skillPreviewView.drawsBackground = true
        skillPreviewView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        skillPreviewView.textContainerInset = NSSize(width: 6, height: 6)
        skillPreviewView.isHorizontallyResizable = false
        skillPreviewView.isVerticallyResizable = true
        skillPreviewView.textContainer?.widthTracksTextView = true
        skillPreviewView.textContainer?.containerSize = NSSize(
            width: previewScroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        previewScroll.documentView = skillPreviewView
        doc.addSubview(previewScroll)
        y -= 136

        let copySkill = NSButton(title: "复制提示词", target: self, action: #selector(copySelectedSkillPrompt))
        copySkill.frame = NSRect(x: 24, y: y, width: 110, height: 28)
        doc.addSubview(copySkill)

        let viewSkill = NSButton(title: "查看完整提示词…", target: self, action: #selector(showSelectedSkillFull))
        viewSkill.frame = NSRect(x: 142, y: y, width: 150, height: 28)
        viewSkill.toolTip = "只读展示当前选中 UK skill 全文；不会写入剪贴板"
        doc.addSubview(viewSkill)

        skillCopyStatus = NSTextField(labelWithString: "")
        skillCopyStatus.font = .systemFont(ofSize: 11)
        skillCopyStatus.textColor = .secondaryLabelColor
        skillCopyStatus.frame = NSRect(x: 300, y: y + 4, width: 130, height: 20)
        doc.addSubview(skillCopyStatus)
        y -= 40

        let viewPrompt = NSButton(
            title: "查看 Agent 全文…",
            target: self,
            action: #selector(showFullPrompt)
        )
        viewPrompt.frame = NSRect(x: 24, y: y, width: 150, height: 28)
        viewPrompt.toolTip = "通用 Agent IO 操作全文（§2.8.2；非单个 UK skill）"
        doc.addSubview(viewPrompt)

        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 340, y: y, width: 90, height: 28)
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
        reloadUKSkillShelf()
    }

    private func reloadUKSkillShelf() {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        ukSkills = AgentSkillsStore.listUKMeetingSkills()
        skillPopup.removeAllItems()
        if ukSkills.isEmpty {
            skillPopup.addItem(withTitle: "（无 UK 技能 — 检查 Bundle 播种）")
            skillPopup.isEnabled = false
            skillPreviewView.string = ""
            return
        }
        skillPopup.isEnabled = true
        for meta in ukSkills {
            skillPopup.addItem(withTitle: "\(meta.title)  ·  \(meta.id)")
        }
        skillPopup.selectItem(at: 0)
        refreshSkillPreview()
    }

    private var selectedSkill: AgentSkillsStore.SkillMeta? {
        let idx = skillPopup.indexOfSelectedItem
        guard idx >= 0, idx < ukSkills.count else { return nil }
        return ukSkills[idx]
    }

    @objc private func skillSelectionChanged() {
        skillCopyStatus.stringValue = ""
        refreshSkillPreview()
    }

    private func refreshSkillPreview() {
        guard let meta = selectedSkill else {
            skillPreviewView.string = ""
            return
        }
        let header = "\(meta.title) (\(meta.id) v\(meta.version))\n"
        let body = meta.examplePreview.isEmpty
            ? "(本技能暂无 Example / Preview 段)"
            : meta.examplePreview
        skillPreviewView.string = header + "\n" + body
    }

    @objc private func copySelectedSkillPrompt() {
        guard let meta = selectedSkill else { return }
        let line = AgentPromptTemplate.makeClipboardIndex(skillFileName: meta.fileName)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
        skillCopyStatus.stringValue = "已复制一行指针"
        AppLog.info(.app, "uk skill clipboard copied id=\(meta.id) chars=\(line.count)")
    }

    @objc private func showSelectedSkillFull() {
        guard let meta = selectedSkill else { return }
        guard let content = try? AgentSkillsStore.readSkill(named: meta.fileName).content else { return }
        let viewer = PromptViewerSheetController(
            text: content,
            title: "\(meta.title)（只读）",
            hint: "完整技能正文仅在此查看；「复制提示词」只复制一行「请阅读 \(meta.fileName)」路径。"
        )
        promptViewer = viewer
        guard let sheet = viewer.window, let parent = window else { return }
        parent.beginSheet(sheet) { [weak self] _ in
            self?.promptViewer = nil
        }
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
