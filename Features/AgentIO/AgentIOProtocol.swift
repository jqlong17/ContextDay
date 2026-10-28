import Foundation

/// Phase 4 本机 MCP / HTTP 协议（§2.9）。
/// Segment 工具只读；agent-skills 工具可读写 Application Support 副本（永不改 Bundle / Segment schema）。
enum AgentIOProtocol {
    /// Segment 首波（只读）。
    static let firstWaveTools: [String] = [
        "search_segments",
        "get_recent",
        "get_window",
        "list_activity",
    ]

    /// 助手技能 / 剪贴板模版（App Support；可更新）。
    static let skillsTools: [String] = [
        "list_agent_skills",
        "get_agent_skill",
        "update_agent_skill",
        "reset_agent_skill",
        "get_clipboard_prompt",
    ]

    /// 非首波：必须返回 unavailable，禁止静默空成功。
    static let unavailableTools: [String] = [
        "summarize_window",
        "export_audio",
    ]

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

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
                page: arguments["page"] as? Int ?? intArg(arguments["page"]),
                maxChars: arguments["max_chars"] as? Int ?? intArg(arguments["max_chars"])
            )
            return try encodeJSON(dto)

        case "get_recent":
            let dto = service.getRecent(
                hours: double(arguments["hours"]),
                limit: arguments["limit"] as? Int ?? intArg(arguments["limit"]),
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

        case "list_agent_skills":
            return try encodeJSON(service.listAgentSkills())

        case "get_agent_skill":
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                throw AgentIOError.invalidArgument("get_agent_skill requires name")
            }
            return try encodeJSON(try service.getAgentSkill(name: name))

        case "update_agent_skill":
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                throw AgentIOError.invalidArgument("update_agent_skill requires name")
            }
            guard let content = arguments["content"] as? String else {
                throw AgentIOError.invalidArgument("update_agent_skill requires content")
            }
            return try encodeJSON(try service.updateAgentSkill(name: name, content: content))

        case "reset_agent_skill":
            let name = arguments["name"] as? String
            return try encodeJSON(try service.resetAgentSkill(name: name))

        case "get_clipboard_prompt":
            return try encodeJSON(service.getClipboardPrompt())

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

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let v as Int64: return v
        case let v as Int: return Int64(v)
        case let v as Double: return Int64(v)
        case let v as NSNumber: return v.int64Value
        default: return nil
        }
    }

    private static func intArg(_ value: Any?) -> Int? {
        switch value {
        case let v as Int: return v
        case let v as Int64: return Int(v)
        case let v as Double: return Int(v)
        case let v as NSNumber: return v.intValue
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
