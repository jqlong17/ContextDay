import Foundation

/// Absolute paths under Application Support for Bundle ID `app.contextday` (Spec §3.4).
enum AppPaths {
    static let bundleIdentifier = "app.contextday"

    /// `~/Library/Application Support/app.contextday/`
    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var databaseDirectory: URL {
        applicationSupportRoot.appendingPathComponent("db", isDirectory: true)
    }

    static var databaseFile: URL {
        databaseDirectory.appendingPathComponent("contextday.sqlite")
    }

    static var audioDirectory: URL {
        applicationSupportRoot.appendingPathComponent("audio", isDirectory: true)
    }

    static var logsDirectory: URL {
        applicationSupportRoot.appendingPathComponent("logs", isDirectory: true)
    }

    static var scratchDirectory: URL {
        applicationSupportRoot.appendingPathComponent("scratch", isDirectory: true)
    }

    /// Creates the Application Support tree (`db/`, `audio/`, `logs/`, `scratch/`).
    @discardableResult
    static func ensureDirectoryTree() throws -> URL {
        let fm = FileManager.default
        for dir in [applicationSupportRoot, databaseDirectory, audioDirectory, logsDirectory, scratchDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return applicationSupportRoot
    }
}
