import Foundation

/// Configurable records root. Default: `~/Downloads/ContextDay`.
/// Preference key: UserDefaults `recordsRootPath`.
enum AppPaths {
    static let bundleIdentifier = "app.contextday"
    static let recordsRootPathKey = "recordsRootPath"

    /// Default when `recordsRootPath` is unset: `~/Downloads/ContextDay`.
    static var defaultRecordsRoot: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("ContextDay", isDirectory: true)
    }

    /// Current records root (`recordsRootPath` → else `defaultRecordsRoot`).
    static var recordsRoot: URL {
        if let path = UserDefaults.standard.string(forKey: recordsRootPathKey), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return defaultRecordsRoot
    }

    /// Persist a new records root (stores absolute path in `recordsRootPath`).
    static func setRecordsRoot(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: recordsRootPathKey)
        UserDefaults.standard.synchronize()
    }

    /// Alias → `recordsRoot` (legacy name from Spec §3.4 Application Support wording).
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

    /// Creates `db/` / `audio/` / `logs/` / `scratch/` under the current `recordsRoot`.
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
