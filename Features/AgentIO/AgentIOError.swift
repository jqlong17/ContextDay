import Foundation

/// Agent IO 错误（§2.9）：首波工具参数问题，或非首波明确 unavailable。
enum AgentIOError: Error, LocalizedError, Equatable {
    case invalidArgument(String)
    case unavailable(tool: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let detail):
            return detail
        case .unavailable(let tool, let reason):
            return "\(tool) unavailable: \(reason)"
        }
    }

    /// 供 JSON / MCP 层序列化。
    var payload: [String: String] {
        switch self {
        case .invalidArgument(let detail):
            return ["error": "invalid_argument", "message": detail]
        case .unavailable(let tool, let reason):
            return ["error": "unavailable", "tool": tool, "message": reason]
        }
    }
}
