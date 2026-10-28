import Foundation

/// §2.9 只读语义工具服务 — Desktop / 测试 / 日后 MCP 共用同一 API。
/// 空库返回空数组，不崩溃。不改 Segment schema。
final class AgentIOService: @unchecked Sendable {
    static let shared = AgentIOService()

    private let store: SegmentStore
    private let defaultPageSize = 50
    private let hardLimit = 500

    init(store: SegmentStore = .shared) {
        self.store = store
    }

    // MARK: - First-wave tools

    /// `search_segments(t0_ms?, t1_ms?, query?, track?, page?, max_chars?)`
    func searchSegments(
        t0Ms: Int64? = nil,
        t1Ms: Int64? = nil,
        query: String? = nil,
        track: SegmentTrack? = nil,
        page: Int? = nil,
        maxChars: Int? = nil
    ) -> [AgentSegmentDTO] {
        let pageIndex = max(0, page ?? 0)
        let rows = store.querySegments(
            t0Ms: t0Ms,
            t1Ms: t1Ms,
            track: track,
            textQuery: query,
            limit: defaultPageSize,
            offset: pageIndex * defaultPageSize
        )
        return rows.map { AgentSegmentDTO(segment: $0, maxChars: maxChars) }
    }

    /// `get_recent(hours? OR limit?, track?)` — 缺省 `hours=24`。
    func getRecent(
        hours: Double? = nil,
        limit: Int? = nil,
        track: SegmentTrack? = nil
    ) -> [AgentSegmentDTO] {
        let cappedLimit = min(hardLimit, max(1, limit ?? hardLimit))
        if let limit, hours == nil {
            let rows = store.queryRecent(limit: cappedLimit, track: track)
            return rows.map { AgentSegmentDTO(segment: $0) }
        }
        let windowHours = hours ?? 24
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let t0 = now - Int64(windowHours * 3_600_000)
        let rows = store.querySegments(
            t0Ms: t0,
            t1Ms: now,
            track: track,
            textQuery: nil,
            limit: cappedLimit,
            offset: 0
        )
        return rows.map { AgentSegmentDTO(segment: $0) }
    }

    /// `get_window(t0_ms, t1_ms, track?)` — 闭区间 `[t0_ms, t1_ms]` 与段有交集即纳入。
    func getWindow(t0Ms: Int64, t1Ms: Int64, track: SegmentTrack? = nil) throws -> [AgentSegmentDTO] {
        guard t1Ms >= t0Ms else {
            throw AgentIOError.invalidArgument("t1_ms must be >= t0_ms")
        }
        let rows = store.querySegments(
            t0Ms: t0Ms,
            t1Ms: t1Ms,
            track: track,
            textQuery: nil,
            limit: hardLimit,
            offset: 0
        )
        return rows.map { AgentSegmentDTO(segment: $0) }
    }

    /// `list_activity(t0_ms?, t1_ms?)` — 按本地日历小时粗分桶计数。
    func listActivity(t0Ms: Int64? = nil, t1Ms: Int64? = nil) -> [AgentActivityBucketDTO] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let end = t1Ms ?? now
        let start = t0Ms ?? (end - 24 * 3_600_000)
        let rows = store.querySegments(
            t0Ms: start,
            t1Ms: end,
            track: nil,
            textQuery: nil,
            limit: hardLimit,
            offset: 0
        )
        let hourMs: Int64 = 3_600_000
        var counts: [Int64: Int] = [:]
        for row in rows {
            let bucket = (row.t0Ms / hourMs) * hourMs
            counts[bucket, default: 0] += 1
        }
        return counts.keys.sorted().map { bucket in
            AgentActivityBucketDTO(
                bucketStartMs: bucket,
                bucketEndMs: bucket + hourMs,
                segmentCount: counts[bucket] ?? 0,
                track: nil
            )
        }
    }

    // MARK: - Non-first-wave (explicit unavailable)

    /// `summarize_window` — 非首波；本机不做摘要。
    func summarizeWindow(t0Ms _: Int64, t1Ms _: Int64) throws -> Never {
        throw AgentIOError.unavailable(
            tool: "summarize_window",
            reason: "not in first wave; leave summarization to the upstream assistant"
        )
    }

    /// `export_audio` — 非首波；首波不导出音频字节。
    func exportAudio(segmentId _: String) throws -> Never {
        throw AgentIOError.unavailable(
            tool: "export_audio",
            reason: "not in first wave; audio export deferred"
        )
    }
}
