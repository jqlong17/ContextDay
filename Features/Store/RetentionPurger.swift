import Foundation

/// Rolling retention by `AppConfig.retentionDays` (Spec §3.4.4).
enum RetentionPurger {
    /// Deletes Segment rows older than cutoff and best-effort removes orphaned audio day folders.
    @discardableResult
    static func purgeIfNeeded(
        store: SegmentStore = .shared,
        config: AppConfig = AppConfigStore.load()
    ) -> Int {
        guard let days = config.retentionDays, days > 0 else { return 0 }
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days) * 86_400_000
        do {
            let removed = try store.deleteSegments(t1BeforeMs: cutoff)
            if removed > 0 {
                NSLog("ContextDay Retention: purged \(removed) segment(s) older than \(days)d")
            }
            return removed
        } catch {
            NSLog("ContextDay Retention: purge failed — \(error.localizedDescription)")
            return 0
        }
    }
}
