import AppKit

/// Read-only sheet showing the full §2.8 prompt / skill brief (never touches pasteboard).
final class PromptViewerSheetController: NSWindowController {
    convenience init(text: String, title: String = "完整提示词（只读）", hint: String? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        self.init(window: window)

        guard let content = window.contentView else { return }

        let hintText = hint
            ?? "仅在本机设置中查看；「复制提示词」只复制一行「请阅读 …」路径指针，不会复制下文。"
        let hintField = NSTextField(labelWithString: hintText)
        hintField.frame = NSRect(x: 16, y: 382, width: 528, height: 28)
        hintField.font = .systemFont(ofSize: 11)
        hintField.textColor = .secondaryLabelColor
        hintField.maximumNumberOfLines = 2
        content.addSubview(hintField)

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 52, width: 528, height: 324))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 510, height: 324))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        scroll.documentView = textView
        content.addSubview(scroll)

        let close = NSButton(title: "关闭", target: self, action: #selector(closeSheet))
        close.frame = NSRect(x: 454, y: 12, width: 90, height: 28)
        content.addSubview(close)
    }

    @objc private func closeSheet() {
        guard let sheet = window, let parent = sheet.sheetParent else {
            window?.close()
            return
        }
        parent.endSheet(sheet)
    }
}
