import AppKit

/// Privacy / local-path / delete-policy copy (Spec §2.6 / §3.4 / 验收#6).
final class AboutPrivacyWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于与隐私"
        window.center()
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let scroll = NSScrollView(frame: content.bounds.insetBy(dx: 16, dy: 48))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 1))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.string = Self.bodyText()
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.font = .systemFont(ofSize: 13)
        scroll.documentView = text
        content.addSubview(scroll)

        let open = NSButton(title: "打开记录文件夹", target: self, action: #selector(openFolder))
        open.frame = NSRect(x: 16, y: 12, width: 140, height: 28)
        content.addSubview(open)

        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.frame = NSRect(x: 420, y: 12, width: 80, height: 28)
        close.autoresizingMask = [.minXMargin]
        content.addSubview(close)
    }

    @objc private func openFolder() {
        do {
            let root = try AppPaths.ensureDirectoryTree()
            NSWorkspace.shared.open(root)
        } catch {
            NSLog("ContextDay: open records folder failed: \(error)")
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }

    private static func bodyText() -> String {
        let root = AppPaths.recordsRoot.path
        let disk = DiskSpaceGuard.status()
        let freeGB = Double(disk.freeBytes) / 1_000_000_000
        return """
        ContextDay — 本机 24h 语音上下文

        隐私
        • 默认本地-only：采集、门控、转写均在本机完成，不上云。
        • 转写权威在 SQLite，不另写每日 txt。
        • 留音默认关闭；开启后仅作证据回听（Opus 档），路径见下。

        本机路径
        • 记录根：\(root)
        • 数据库：\(root)/db/contextday.sqlite
        • 可选音频：\(root)/audio/YYYY-MM-DD/{mic|system}/
        • 当前可用空间约 \(String(format: "%.1f", freeGB)) GB\(disk.warning.map { "（\($0)）" } ?? "")

        删除与保留
        • 设置里「保留天数」默认 30；留空 = 不自动删。
        • 滚动删除会去掉早于阈值的 Segment 行及对应 audio/ 日目录。
        • 可在 Finder 中手动删除记录根下文件；删除前请确认。
        • 「清空」：删除 db 与 audio 后重启 App 会重建空库。

        锁屏 / 睡眠（能力边界）
        • 睡眠：系统睡眠时采集暂停；唤醒后需再次「开始录音」才会继续（不自动偷采）。
        • 锁屏：在用户已授权麦克风且 App 仍在前台/后台运行时，麦轨可能继续；系统声依赖 ScreenCaptureKit 授权，锁屏后可能中断。
        • 正式 24h 无人值守仍需保持 Mac 唤醒或接电源 + 防止自动睡眠。

        Agent IO
        • 剪贴板提示词（右键）与本机 HTTP 127.0.0.1:18787（空闲回退 18787–18797） / MCP stdio（--mcp）只读暴露同一 SQLite。
        • 详见 docs/agent-io-mcp.md。

        ASR：SenseVoice Core ML int8（本机）。门控：YAMNet；Music 与 Speech 同高时 Music 优先（有 BGM 的说话可能被标成 music）。
        """
    }
}
