import Foundation

/// Configurable on-disk records root (Phase 0 bring-up default: `~/Downloads/ContextDay`).
/// Spec §3.4 still documents Application Support; runtime root is user-selectable.
enum AppPaths {
    static let bundleIdentifier = "app.contextday"
    static let recordsRootPathKey = "recordsRootPath"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: bundleIdentifier) ?? .standard
    }

    /// Default records root when no preference is set: `~/Downloads/ContextDay`.
    static var defaultRecordsRoot: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("ContextDay", isDirectory: true)
    }

    /// Current records root (UserDefaults `recordsRootPath`, else `defaultRecordsRoot`).
    static var recordsRoot: URL {
        if let path = defaults.string(forKey: recordsRootPathKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultRecordsRoot
    }

    /// Persists a new records root directory path.
    static func setRecordsRoot(_ url: URL) {
        defaults.set(url.standardizedFileURL.path, forKey: recordsRootPathKey)
    }

    /// Legacy alias — same as `recordsRoot` (call sites / prompt copy).
    static var applicationSupportRoot: URL { recordsRoot }

    static var databaseDirectory: URL {
        recordsRoot.appendingPathComponent("db", isDirectory: true)
    }

    static var databaseFile: URL {
        databaseDirectory.appendingPathComponent("contextday.sqlite")
    }

    static var audioDirectory: URL {
        recordsRoot.appendingPathComponent("audio", isDirectory: true)
    }

    static var logsDirectory: URL {
        recordsRoot.appendingPathComponent("logs", isDirectory: true)
    }

    static var scratchDirectory: URL {
        recordsRoot.appendingPathComponent("scratch", isDirectory: true)
    }

    /// Creates the records tree (`db/`, `audio/`, `logs/`, `scratch/`) under the current root.
    @discardableResult
    static func ensureDirectoryTree() throws -> URL {
        let fm = FileManager.default
        let root = recordsRoot
        for dir in [root, databaseDirectory, audioDirectory, logsDirectory, scratchDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return root
    }
}
