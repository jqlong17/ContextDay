import Foundation

/// Resolves preferred Agent IO HTTP port (Spec Phase 4).
/// Default scan starts at **18787** (8787 is often taken by other local services).
enum AgentIOPort {
    static let defaultsKey = "agentIOHTTPPort"
    static let infoPlistKey = "ContextDayAgentIOPort"
    static let defaultPreferred: UInt16 = 18_787

    /// Priority: `--port N` → UserDefaults → Info.plist → 18787.
    static func preferred(arguments: [String] = CommandLine.arguments) -> UInt16 {
        if let idx = arguments.firstIndex(of: "--port"),
           idx + 1 < arguments.count,
           let parsed = UInt16(arguments[idx + 1]),
           parsed > 0 {
            return parsed
        }
        for arg in arguments where arg.hasPrefix("--port=") {
            let raw = String(arg.dropFirst("--port=".count))
            if let parsed = UInt16(raw), parsed > 0 { return parsed }
        }
        if let stored = UserDefaults.standard.object(forKey: defaultsKey) as? Int,
           stored > 0, stored <= 65_535 {
            return UInt16(stored)
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? Int,
           plist > 0, plist <= 65_535 {
            return UInt16(plist)
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
           let parsed = UInt16(plist), parsed > 0 {
            return parsed
        }
        return defaultPreferred
    }

    static func save(_ port: UInt16) {
        UserDefaults.standard.set(Int(port), forKey: defaultsKey)
    }
}
