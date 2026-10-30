import Foundation

/// Cold-start “all good” gate for one orb ready-blink (Spec §2.7.4).
/// Ready = mic authorized + screen recording authorized + records root writable.
enum LaunchReadyGate {
    struct Result: Equatable, Sendable {
        var micAuthorized: Bool
        var screenAuthorized: Bool
        var recordsWritable: Bool

        var isReady: Bool {
            micAuthorized && screenAuthorized && recordsWritable
        }
    }

    static func evaluate(
        permissions: PermissionSnapshot = PermissionStatus.snapshot(),
        recordsRoot: URL = AppPaths.recordsRoot,
        fileManager: FileManager = .default
    ) -> Result {
        Result(
            micAuthorized: permissions.entry(.microphone)?.state == .authorized,
            screenAuthorized: permissions.entry(.screenRecording)?.state == .authorized,
            recordsWritable: isWritableDirectory(recordsRoot, fileManager: fileManager)
        )
    }

    static func isReady(
        permissions: PermissionSnapshot = PermissionStatus.snapshot(),
        recordsRoot: URL = AppPaths.recordsRoot,
        fileManager: FileManager = .default
    ) -> Bool {
        evaluate(permissions: permissions, recordsRoot: recordsRoot, fileManager: fileManager).isReady
    }

    /// True when `root` exists (or can be created) and is writable.
    static func isWritableDirectory(_ root: URL, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: root.path, isDirectory: &isDir) {
            do {
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }
        return fileManager.isWritableFile(atPath: root.path)
    }
}
