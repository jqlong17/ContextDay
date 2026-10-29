import Foundation

/// Agent IO 错误（01 §2.9 / 02 §2.8）：统一 JSON 形状 `{error, message, tool?}`.
enum AgentIOError: Error, LocalizedError, Equatable {
    case invalidArgument(String)
    case notFound(String)
    case unavailable(tool: String, reason: String)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let detail):
            return detail
        case .notFound(let detail):
            return detail
        case .unavailable(let tool, let reason):
            return "\(tool) unavailable: \(reason)"
        case .internalError(let detail):
            return detail
        }
    }

    /// Stable machine code for JSON `error` field.
    var code: String {
        switch self {
        case .invalidArgument: return "invalid_argument"
        case .notFound: return "not_found"
        case .unavailable: return "unavailable"
        case .internalError: return "internal"
        }
    }

    /// HTTP status aligned with 02 §2.8.
    var httpStatus: Int {
        switch self {
        case .invalidArgument: return 400
        case .notFound: return 404
        case .unavailable: return 501
        case .internalError: return 500
        }
    }

    /// 供 JSON / MCP 层序列化 — always includes `error` + `message`.
    var payload: [String: String] {
        switch self {
        case .invalidArgument(let detail):
            return ["error": "invalid_argument", "message": detail]
        case .notFound(let detail):
            return ["error": "not_found", "message": detail]
        case .unavailable(let tool, let reason):
            return ["error": "unavailable", "tool": tool, "message": reason]
        case .internalError(let detail):
            return ["error": "internal", "message": detail]
        }
    }
}
