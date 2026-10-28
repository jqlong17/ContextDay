import Foundation
import SQLite3

/// SQLite timeline store (Spec §3.3 / §3.4). Phase 0: create empty DB + Segment schema.
final class SegmentStore: @unchecked Sendable {
    static let shared = SegmentStore()

    private var db: OpaquePointer?
    private var openDatabasePath: String?
    private let lock = NSLock()

    private init() {}

    deinit {
        closeDatabaseUnlocked()
    }

    /// Ensures records dirs exist, then closes any open sqlite handle and reopens /
    /// creates schema at `AppPaths.databaseFile` (follows `recordsRoot` changes).
    func prepareApplicationSupport() throws {
        try AppPaths.ensureDirectoryTree()
        try reopenDatabaseAtCurrentRoot()
        try createSchemaIfNeeded()
    }

    /// Close existing handle (if any), then open/create DB at the current records root.
    private func reopenDatabaseAtCurrentRoot() throws {
        lock.lock()
        defer { lock.unlock() }

        closeDatabaseUnlocked()

        let path = AppPaths.databaseFile.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "nil handle"
            if let handle { sqlite3_close(handle) }
            throw StoreError.openFailed(message)
        }
        db = handle
        openDatabasePath = path
    }

    private func closeDatabaseUnlocked() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
        openDatabasePath = nil
    }

    // MARK: - Writes

    func insertSegment(_ segment: Segment) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { throw StoreError.notOpen }

        let sql = """
        INSERT INTO segment (
            id, track, t0_ms, t1_ms, tz_at_capture, text, gate_label, audio_path,
            source_segment_ids, created_at_ms, merged_at_ms, merge_gap_ms,
            asr_model_id, asr_model_version
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.schemaFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        let sourceJSON: String
        if let data = try? JSONEncoder().encode(segment.sourceSegmentIds.map { $0.uuidString.lowercased() }),
           let s = String(data: data, encoding: .utf8) {
            sourceJSON = s
        } else {
            sourceJSON = "[]"
        }

        func bindText(_ idx: Int32, _ value: String?) {
            if let value {
                sqlite3_bind_text(statement, idx, value, -1, Self.sqliteTransient)
            } else {
                sqlite3_bind_null(statement, idx)
            }
        }

        sqlite3_bind_text(statement, 1, segment.id.uuidString.lowercased(), -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 2, segment.track.rawValue, -1, Self.sqliteTransient)
        sqlite3_bind_int64(statement, 3, segment.t0Ms)
        sqlite3_bind_int64(statement, 4, segment.t1Ms)
        bindText(5, segment.tzAtCapture)
        bindText(6, segment.text)
        bindText(7, segment.gateLabel?.rawValue)
        bindText(8, segment.audioPath)
        sqlite3_bind_text(statement, 9, sourceJSON, -1, Self.sqliteTransient)
        sqlite3_bind_int64(statement, 10, segment.createdAtMs)
        if let v = segment.mergedAtMs { sqlite3_bind_int64(statement, 11, v) } else { sqlite3_bind_null(statement, 11) }
        if let v = segment.mergeGapMs { sqlite3_bind_int64(statement, 12, Int64(v)) } else { sqlite3_bind_null(statement, 12) }
        bindText(13, segment.asrModelId)
        bindText(14, segment.asrModelVersion)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.schemaFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Read queries (Agent IO §2.9; empty DB → [])

    /// Overlap with `[t0Ms, t1Ms]` when provided; optional track / LIKE query; newest-first.
    func querySegments(
        t0Ms: Int64?,
        t1Ms: Int64?,
        track: SegmentTrack?,
        textQuery: String?,
        limit: Int,
        offset: Int
    ) -> [Segment] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        var sql = """
        SELECT id, track, t0_ms, t1_ms, tz_at_capture, text, gate_label,
               audio_path, source_segment_ids, created_at_ms, merged_at_ms,
               merge_gap_ms, asr_model_id, asr_model_version
        FROM segment
        WHERE 1=1
        """
        var args: [BindValue] = []
        if let t0Ms {
            sql += " AND t1_ms >= ?"
            args.append(.int64(t0Ms))
        }
        if let t1Ms {
            sql += " AND t0_ms <= ?"
            args.append(.int64(t1Ms))
        }
        if let track {
            sql += " AND track = ?"
            args.append(.text(track.rawValue))
        }
        if let textQuery {
            let trimmed = textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sql += " AND IFNULL(text, '') LIKE ?"
                args.append(.text("%\(trimmed)%"))
            }
        }
        sql += " ORDER BY t0_ms DESC LIMIT ? OFFSET ?"
        args.append(.int64(Int64(max(0, limit))))
        args.append(.int64(Int64(max(0, offset))))

        return Self.runSelect(db: db, sql: sql, args: args)
    }

    func queryRecent(limit: Int, track: SegmentTrack?) -> [Segment] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        var sql = """
        SELECT id, track, t0_ms, t1_ms, tz_at_capture, text, gate_label,
               audio_path, source_segment_ids, created_at_ms, merged_at_ms,
               merge_gap_ms, asr_model_id, asr_model_version
        FROM segment
        WHERE 1=1
        """
        var args: [BindValue] = []
        if let track {
            sql += " AND track = ?"
            args.append(.text(track.rawValue))
        }
        sql += " ORDER BY t0_ms DESC LIMIT ?"
        args.append(.int64(Int64(max(0, limit))))
        return Self.runSelect(db: db, sql: sql, args: args)
    }

    private enum BindValue {
        case text(String)
        case int64(Int64)
    }

    /// SQLITE_TRANSIENT — copy bind text; string lifetime is not guaranteed after bind returns.
    private static let sqliteTransient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private static func runSelect(db: OpaquePointer, sql: String, args: [BindValue]) -> [Segment] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            NSLog("ContextDay SegmentStore: prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        defer { sqlite3_finalize(statement) }

        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case .text(let s):
                sqlite3_bind_text(statement, idx, s, -1, sqliteTransient)
            case .int64(let v):
                sqlite3_bind_int64(statement, idx, v)
            }
        }

        var rows: [Segment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let segment = mapRow(statement) {
                rows.append(segment)
            }
        }
        return rows
    }

    private static func mapRow(_ statement: OpaquePointer) -> Segment? {
        func text(_ col: Int32) -> String? {
            guard let c = sqlite3_column_text(statement, col) else { return nil }
            return String(cString: c)
        }
        func int64(_ col: Int32) -> Int64 { sqlite3_column_int64(statement, col) }
        func intOpt(_ col: Int32) -> Int? {
            sqlite3_column_type(statement, col) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, col))
        }
        func int64Opt(_ col: Int32) -> Int64? {
            sqlite3_column_type(statement, col) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, col)
        }

        guard let idText = text(0), let id = UUID(uuidString: idText),
              let trackRaw = text(1), let track = SegmentTrack(rawValue: trackRaw) else {
            return nil
        }
        let gate: GateLabel? = text(6).flatMap { GateLabel(rawValue: $0) }
        let sourceIds: [UUID]
        if let raw = text(8),
           let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            sourceIds = arr.compactMap { UUID(uuidString: $0) }
        } else {
            sourceIds = []
        }

        return Segment(
            id: id,
            track: track,
            t0Ms: int64(2),
            t1Ms: int64(3),
            tzAtCapture: text(4),
            text: text(5),
            gateLabel: gate,
            audioPath: text(7),
            sourceSegmentIds: sourceIds,
            createdAtMs: int64(9),
            mergedAtMs: int64Opt(10),
            mergeGapMs: intOpt(11),
            asrModelId: text(12),
            asrModelVersion: text(13)
        )
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
