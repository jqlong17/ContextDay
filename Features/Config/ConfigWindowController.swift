import AppKit

/// Minimal config surface (Spec §2.2 / §3.3.5).
final class ConfigWindowController: NSWindowController {
    private var gateButton: NSButton!
    private var keepAudioButton: NSButton!
    private var qualityPopup: NSPopUpButton!
    private var retentionField: NSTextField!
    private var systemAudioButton: NSButton!
    private var estimateLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
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
        var y = 230.0

        gateButton = NSButton(checkboxWithTitle: "分类过滤（YAMNet）", target: self, action: #selector(changed))
        gateButton.frame = NSRect(x: 24, y: y, width: 360, height: 24)
        content.addSubview(gateButton)
        y -= 36

        keepAudioButton = NSButton(checkboxWithTitle: "保留音频（证据回听）", target: self, action: #selector(changed))
        keepAudioButton.frame = NSRect(x: 24, y: y, width: 360, height: 24)
        content.addSubview(keepAudioButton)
        y -= 36

        let qLabel = NSTextField(labelWithString: "音频质量")
        qLabel.frame = NSRect(x: 24, y: y, width: 100, height: 24)
        content.addSubview(qLabel)
        qualityPopup = NSPopUpButton(frame: NSRect(x: 130, y: y, width: 160, height: 26))
        qualityPopup.addItems(withTitles: ["Opus 12 kbps", "Opus 24 kbps（默认）", "Opus 64 kbps"])
        qualityPopup.target = self
        qualityPopup.action = #selector(changed)
        content.addSubview(qualityPopup)
        y -= 36

        let rLabel = NSTextField(labelWithString: "保留天数")
        rLabel.frame = NSRect(x: 24, y: y, width: 100, height: 24)
        content.addSubview(rLabel)
        retentionField = NSTextField(frame: NSRect(x: 130, y: y, width: 80, height: 24))
        retentionField.placeholderString = "30 / 空=不自动删"
        retentionField.target = self
        retentionField.action = #selector(changed)
        content.addSubview(retentionField)
        y -= 36

        systemAudioButton = NSButton(checkboxWithTitle: "采集系统声（ScreenCaptureKit）", target: self, action: #selector(changed))
        systemAudioButton.frame = NSRect(x: 24, y: y, width: 360, height: 24)
        content.addSubview(systemAudioButton)
        y -= 40

        estimateLabel = NSTextField(labelWithString: "")
        estimateLabel.frame = NSRect(x: 24, y: y, width: 370, height: 40)
        estimateLabel.maximumNumberOfLines = 2
        content.addSubview(estimateLabel)

        let save = NSButton(title: "保存", target: self, action: #selector(save))
        save.frame = NSRect(x: 300, y: 16, width: 90, height: 28)
        content.addSubview(save)
    }

    private func loadFromStore() {
        let cfg = AppConfigStore.load()
        gateButton.state = cfg.gateEnabled ? .on : .off
        keepAudioButton.state = cfg.keepAudio ? .on : .off
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
        refreshEstimate()
    }

    @objc private func changed() { refreshEstimate() }

    private func refreshEstimate() {
        var cfg = currentConfig()
        estimateLabel.stringValue = cfg.keepAudio
            ? String(format: "开留音时约 %.2f GB/天（全天粗算，未计门控折扣）", cfg.estimatedKeepAudioGBPerDay)
            : "留音默认关；开启后按 Opus 档估算占用。"
    }

    private func currentConfig() -> AppConfig {
        var cfg = AppConfigStore.load()
        cfg.gateEnabled = gateButton.state == .on
        cfg.keepAudio = keepAudioButton.state == .on
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
        cfg.normalize()
        return cfg
    }

    @objc private func save() {
        AppConfigStore.save(currentConfig())
        window?.close()
    }
}
