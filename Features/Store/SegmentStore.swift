import Foundation
import SQLite3

/// SQLite timeline store (Spec §3.3 / §3.4). Phase 0: create empty DB + Segment schema.
final class SegmentStore: @unchecked Sendable {
    static let shared = SegmentStore()

    private var db: OpaquePointer?
    private let lock = NSLock()

    private init() {}

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    /// Ensures Application Support dirs exist and opens / creates `contextday.sqlite` with Segment table.
    func prepareApplicationSupport() throws {
        try AppPaths.ensureDirectoryTree()
        try openDatabaseIfNeeded()
        try createSchemaIfNeeded()
    }

    private func openDatabaseIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        guard db == nil else { return }

        let path = AppPaths.databaseFile.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw StoreError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
    }

    private func createSchemaIfNeeded() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS segment (
            id TEXT PRIMARY KEY NOT NULL,
            track TEXT NOT NULL CHECK (track IN ('mic', 'system')),
            t0_ms INTEGER NOT NULL,
            t1_ms INTEGER NOT NULL,
            tz_at_capture TEXT,
            text TEXT,
            gate_label TEXT CHECK (gate_label IS NULL OR gate_label IN ('speech', 'music', 'other')),
            audio_path TEXT,
            source_segment_ids TEXT,
            created_at_ms INTEGER NOT NULL,
            merged_at_ms INTEGER,
            merge_gap_ms INTEGER,
            asr_model_id TEXT,
            asr_model_version TEXT,
            CHECK (t1_ms > t0_ms)
        );
        CREATE INDEX IF NOT EXISTS idx_segment_track_t0 ON segment (track, t0_ms);
        CREATE INDEX IF NOT EXISTS idx_segment_t0 ON segment (t0_ms);
        """

        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw StoreError.notOpen }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw StoreError.schemaFailed(message)
        }
    }

    enum StoreError: Error, LocalizedError {
        case openFailed(String)
        case notOpen
        case schemaFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let detail): return "SQLite open failed: \(detail)"
            case .notOpen: return "SQLite database is not open"
            case .schemaFailed(let detail): return "SQLite schema failed: \(detail)"
            }
        }
    }
}
