import AppKit

/// Simple timeline reading SQLite (Spec Phase 2 light UI).
final class TimelineWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var rows: [Segment] = []
    private let table = NSTableView()
    private let scroll = NSScrollView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ContextDay 时间线"
        window.center()
        self.init(window: window)
        buildUI()
        reload()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.frame = content.bounds
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)

        table.headerView = NSTableHeaderView()
        for (id, title, width) in [
            ("t0", "开始", 140.0),
            ("track", "轨", 60.0),
            ("gate", "门控", 70.0),
            ("text", "转写", 400.0),
        ] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        scroll.documentView = table

        let reloadBtn = NSButton(title: "刷新", target: self, action: #selector(reload))
        reloadBtn.frame = NSRect(x: content.bounds.width - 90, y: content.bounds.height - 28, width: 70, height: 24)
        reloadBtn.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(reloadBtn)
    }

    @objc func reload() {
        rows = SegmentStore.shared.queryRecent(limit: 200, track: nil)
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let seg = rows[row]
        let id = tableColumn?.identifier.rawValue ?? ""
        let value: String
        switch id {
        case "t0":
            value = Self.format(ms: seg.t0Ms)
        case "track":
            value = seg.track.rawValue
        case "gate":
            value = seg.gateLabel?.rawValue ?? "—"
        default:
            value = seg.text ?? ""
        }
        let cell = NSTextField(labelWithString: value)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    private static func format(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}
