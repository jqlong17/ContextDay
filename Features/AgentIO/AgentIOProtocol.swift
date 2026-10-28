import Foundation

/// Phase 4 可挂的本机 MCP / HTTP 协议骨架（§2.9）。
/// 本 PR 不引入 MCP SDK；仅固定工具名、参数与 JSON 结果形状，供 Desktop / 测试直接调 `AgentIOService`。
enum AgentIOProtocol {
    /// 首波工具名（与 Spec §2.9.1 一致）。
    static let firstWaveTools: [String] = [
        "search_segments",
        "get_recent",
        "get_window",
        "list_activity",
    ]

    /// 非首波：必须返回 unavailable，禁止静默空成功。
    static let unavailableTools: [String] = [
        "summarize_window",
        "export_audio",
    ]

    /// 统一 JSON 编码（snake_case via DTO CodingKeys）。
    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// 轻量「本地 MCP 风格」调度：按工具名分发到 `AgentIOService`。
    /// 日后正式 MCP Server 只需把 JSON-RPC/stdio 解析后转到此处。
    static func dispatch(
        tool: String,
        arguments: [String: Any],
        service: AgentIOService = .shared
    ) throws -> Data {
        switch tool {
        case "search_segments":
            let dto = service.searchSegments(
                t0Ms: int64(arguments["t0_ms"]),
                t1Ms: int64(arguments["t1_ms"]),
                query: arguments["query"] as? String,
                track: track(arguments["track"]),
                page: arguments["page"] as? Int,
                maxChars: arguments["max_chars"] as? Int
            )
            return try encodeJSON(dto)

        case "get_recent":
            let dto = service.getRecent(
                hours: double(arguments["hours"]),
                limit: arguments["limit"] as? Int,
                track: track(arguments["track"])
            )
            return try encodeJSON(dto)

        case "get_window":
            guard let t0 = int64(arguments["t0_ms"]), let t1 = int64(arguments["t1_ms"]) else {
                throw AgentIOError.invalidArgument("get_window requires t0_ms and t1_ms")
            }
            let dto = try service.getWindow(t0Ms: t0, t1Ms: t1, track: track(arguments["track"]))
            return try encodeJSON(dto)

        case "list_activity":
            let dto = service.listActivity(
                t0Ms: int64(arguments["t0_ms"]),
                t1Ms: int64(arguments["t1_ms"])
            )
            return try encodeJSON(dto)

        case "summarize_window":
            throw AgentIOError.unavailable(
                tool: "summarize_window",
                reason: "not in first wave; leave summarization to the upstream assistant"
            )

        case "export_audio":
            throw AgentIOError.unavailable(
                tool: "export_audio",
                reason: "not in first wave; audio export deferred"
            )

        default:
            throw AgentIOError.unavailable(tool: tool, reason: "unknown tool")
        }
    }

    // MARK: - Arg helpers

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let v as Int64: return v
        case let v as Int: return Int64(v)
        case let v as Double: return Int64(v)
        case let v as NSNumber: return v.int64Value
        default: return nil
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return nil
        }
    }

    private static func track(_ value: Any?) -> SegmentTrack? {
        guard let raw = value as? String else { return nil }
        return SegmentTrack(rawValue: raw)
    }
}

/*
 Phase 4 MCP 挂载示意（勿在本 PR 引入 SDK）：

   stdio / HTTP JSON-RPC
        │
        ▼
   AgentIOProtocol.dispatch(tool:arguments:)
        │
        ▼
   AgentIOService  →  SegmentStore (SQLite 只读查询)

 工具名与 §2.9 保持一致；传输层可替换，服务层不变。
*/
