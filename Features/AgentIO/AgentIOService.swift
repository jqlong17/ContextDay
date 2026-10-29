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

    // MARK: - Agent skills (App Support writable copy; never Bundle / never Segment)

    /// `list_agent_skills`
    func listAgentSkills() -> AgentSkillsListDTO {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        return AgentSkillsListDTO(
            rootPath: AgentSkillsStore.absoluteSkillsRootPath,
            skills: AgentSkillsStore.listSkills().map {
                AgentSkillFileDTO(
                    name: $0.name,
                    path: $0.path,
                    bytes: $0.bytes,
                    packaged: $0.packaged,
                    localOverride: $0.localOverride
                )
            }
        )
    }

    /// `get_agent_skill(name)`
    func getAgentSkill(name: String) throws -> AgentSkillContentDTO {
        do {
            let result = try AgentSkillsStore.readSkill(named: name)
            return AgentSkillContentDTO(name: name, path: result.path, content: result.content)
        } catch let err as AgentSkillsStore.AgentSkillsError {
            throw mapSkillsError(err)
        }
    }

    /// `update_agent_skill(name, content)` — App Support only.
    func updateAgentSkill(name: String, content: String) throws -> AgentSkillWriteDTO {
        do {
            let path = try AgentSkillsStore.updateSkill(named: name, content: content)
            return AgentSkillWriteDTO(name: name, path: path, updated: true)
        } catch let err as AgentSkillsStore.AgentSkillsError {
            throw mapSkillsError(err)
        }
    }

    /// `reset_agent_skill(name?)` — re-copy from Bundle; `name` nil resets all packaged templates.
    func resetAgentSkill(name: String?) throws -> AgentSkillResetDTO {
        do {
            let paths = try AgentSkillsStore.resetToBundled(name: name)
            return AgentSkillResetDTO(resetPaths: paths)
        } catch let err as AgentSkillsStore.AgentSkillsError {
            throw mapSkillsError(err)
        }
    }

    /// `get_clipboard_prompt` — same short index as pasteboard (Spec §2.8); never the full brief.
    func getClipboardPrompt() -> AgentClipboardPromptDTO {
        _ = AgentSkillsStore.ensureSeededFromBundle()
        let text = AgentPromptTemplate.makeClipboardIndex(recordsRoot: AppPaths.recordsRoot)
        return AgentClipboardPromptDTO(
            text: text,
            kind: "index",
            skillsRootPath: AgentSkillsStore.absoluteSkillsRootPath,
            recordsRootPath: AppPaths.recordsRoot.path
        )
    }

    /// `self_check` — offline-friendly triage snapshot (permissions, DB, models, desync).
    func selfCheck() -> SelfCheck.Report {
        SelfCheck.run()
    }

    private func mapSkillsError(_ err: AgentSkillsStore.AgentSkillsError) -> AgentIOError {
        switch err {
        case .notFound(let n):
            return .notFound("skill not found: \(n)")
        case .invalidName(let n), .notWritable(let n), .notResettable(let n):
            return .invalidArgument(err.errorDescription ?? n)
        case .bundleMissing:
            return .invalidArgument(err.errorDescription ?? "bundle missing")
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

// MARK: - Skills DTOs

struct AgentSkillsListDTO: Codable, Equatable, Sendable {
    var rootPath: String
    var skills: [AgentSkillFileDTO]

    enum CodingKeys: String, CodingKey {
        case rootPath = "root_path"
        case skills
    }
}

struct AgentSkillFileDTO: Codable, Equatable, Sendable {
    var name: String
    var path: String
    var bytes: Int
    var packaged: Bool
    var localOverride: Bool

    enum CodingKeys: String, CodingKey {
        case name, path, bytes, packaged
        case localOverride = "local_override"
    }
}

struct AgentSkillContentDTO: Codable, Equatable, Sendable {
    var name: String
    var path: String
    var content: String
}

struct AgentSkillWriteDTO: Codable, Equatable, Sendable {
    var name: String
    var path: String
    var updated: Bool
}

struct AgentSkillResetDTO: Codable, Equatable, Sendable {
    var resetPaths: [String]

    enum CodingKeys: String, CodingKey {
        case resetPaths = "reset_paths"
    }
}

struct AgentClipboardPromptDTO: Codable, Equatable, Sendable {
    /// Short clipboard index (never the full proprietary brief).
    var text: String
    /// Always `"index"` — pasteboard / tool share the same short body.
    var kind: String
    var skillsRootPath: String
    var recordsRootPath: String

    enum CodingKeys: String, CodingKey {
        case text, kind
        case skillsRootPath = "skills_root_path"
        case recordsRootPath = "records_root_path"
    }
}
