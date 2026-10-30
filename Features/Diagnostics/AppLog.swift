import Foundation
import os

/// Structured logging for ContextDay.
/// OSLog always; optional daily file under `recordsRoot/logs/` (Spec §3.4) for triage.
/// Privacy: never pass raw transcript text at `.info` — lengths / ids only.
enum AppLog {
    static let subsystem = "app.contextday"

    enum Category: String {
        case app
        case permission
        case capture
        case keepAudio = "keep_audio"
        case gate
        case vad
        case asr
        case agentIO = "agent_io"
        case store
    }

    private static let loggers: [Category: Logger] = [
        .app: Logger(subsystem: subsystem, category: Category.app.rawValue),
        .permission: Logger(subsystem: subsystem, category: Category.permission.rawValue),
        .capture: Logger(subsystem: subsystem, category: Category.capture.rawValue),
        .keepAudio: Logger(subsystem: subsystem, category: Category.keepAudio.rawValue),
        .gate: Logger(subsystem: subsystem, category: Category.gate.rawValue),
        .vad: Logger(subsystem: subsystem, category: Category.vad.rawValue),
        .asr: Logger(subsystem: subsystem, category: Category.asr.rawValue),
        .agentIO: Logger(subsystem: subsystem, category: Category.agentIO.rawValue),
        .store: Logger(subsystem: subsystem, category: Category.store.rawValue),
    ]

    private static let fileLock = NSLock()
    private static var fileLoggingEnabled = true

    static func setFileLoggingEnabled(_ enabled: Bool) {
        fileLoggingEnabled = enabled
    }

    static func debug(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        loggers[category]?.debug("\(text, privacy: .public)")
        // Debug stays OSLog-only — avoid daily-file spam.
    }

    static func info(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        loggers[category]?.info("\(text, privacy: .public)")
        appendFile(level: "info", category: category, message: text)
    }

    static func warn(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        loggers[category]?.warning("\(text, privacy: .public)")
        appendFile(level: "warn", category: category, message: text)
    }

    static func error(_ category: Category, _ message: @autoclosure () -> String) {
        let text = message()
        loggers[category]?.error("\(text, privacy: .public)")
        appendFile(level: "error", category: category, message: text)
    }

    // MARK: - Optional durable file (Spec §3.4 `logs/`)

    private static func appendFile(level: String, category: Category, message: String) {
        guard fileLoggingEnabled else { return }
        fileLock.lock()
        defer { fileLock.unlock() }
        do {
            let dir = try AppPaths.ensureDirectoryTree()
            _ = dir
            let day = Self.dayStamp()
            let url = AppPaths.logsDirectory.appendingPathComponent("contextday-\(day).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let line = "\(isoNow()) [\(level)] [\(category.rawValue)] \(message)\n"
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            // Never recurse into AppLog from file sink failure.
            NSLog("[ContextDay] log file write soft-fail: \(error.localizedDescription)")
        }
    }

    private static func dayStamp() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
