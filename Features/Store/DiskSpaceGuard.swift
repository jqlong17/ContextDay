import Foundation

/// Spec §3.4.4 / §3.5 — stop new keep-audio when free space is critically low.
enum DiskSpaceGuard {
    /// Below this free capacity on the records volume, block new keep-audio writes.
    static let minFreeBytesForKeepAudio: Int64 = 500_000_000 // 500 MB

    /// Soft warn threshold (still allows keep-audio but surfaces a status string).
    static let warnFreeBytes: Int64 = 2_000_000_000 // 2 GB

    struct Status: Equatable {
        var freeBytes: Int64
        var blockKeepAudio: Bool
        var warning: String?
    }

    static func status(at root: URL = AppPaths.recordsRoot) -> Status {
        let free = freeBytes(at: root) ?? Int64.max
        if free < minFreeBytesForKeepAudio {
            return Status(
                freeBytes: free,
                blockKeepAudio: true,
                warning: String(
                    format: "磁盘空间不足（约 %.1f GB 可用）— 已停留音；转写仍可只写文本",
                    Double(free) / 1_000_000_000
                )
            )
        }
        if free < warnFreeBytes {
            return Status(
                freeBytes: free,
                blockKeepAudio: false,
                warning: String(
                    format: "磁盘空间偏低（约 %.1f GB 可用）— 建议缩短保留天数或关留音",
                    Double(free) / 1_000_000_000
                )
            )
        }
        return Status(freeBytes: free, blockKeepAudio: false, warning: nil)
    }

    static func freeBytes(at url: URL) -> Int64? {
        let path = url.path
        guard let vals = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let cap = vals.volumeAvailableCapacityForImportantUsage else {
            // Fallback for older keys / non-APFS.
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
               let free = attrs[.systemFreeSize] as? NSNumber {
                return free.int64Value
            }
            return nil
        }
        return cap
    }
}
