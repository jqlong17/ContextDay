import Foundation

/// JSON-friendly Segment projection for Agent IO (01 §2.9 + 02 §2.4). snake_case keys.
/// Stable field names for LLM tool calling; optional paths for minutes / replay.
/// ISO-8601 fields are **derived** — authority remains `t0_ms` / `t1_ms`.
struct AgentSegmentDTO: Codable, Equatable, Sendable {
    var segmentId: String
    var t0Ms: Int64
    var t1Ms: Int64
    var t0Iso: String
    var t1Iso: String
    var track: String
    var gateLabel: String?
    var text: String?
    /// IANA tz at capture (e.g. Asia/Shanghai) — helps local wall-clock in minutes.
    var tzAtCapture: String?
    /// Relative to records root when keep_audio wrote a clip; null if none.
    var audioPath: String?

    enum CodingKeys: String, CodingKey {
        case segmentId = "segment_id"
        case t0Ms = "t0_ms"
        case t1Ms = "t1_ms"
        case t0Iso = "t0_iso"
        case t1Iso = "t1_iso"
        case track
        case gateLabel = "gate_label"
        case text
        case tzAtCapture = "tz_at_capture"
        case audioPath = "audio_path"
    }

    init(segment: Segment, maxChars: Int? = nil) {
        segmentId = segment.id.uuidString.lowercased()
        t0Ms = segment.t0Ms
        t1Ms = segment.t1Ms
        t0Iso = AgentIOTime.iso8601(epochMs: segment.t0Ms, timeZoneIdentifier: segment.tzAtCapture)
        t1Iso = AgentIOTime.iso8601(epochMs: segment.t1Ms, timeZoneIdentifier: segment.tzAtCapture)
        track = segment.track.rawValue
        gateLabel = segment.gateLabel?.rawValue
        tzAtCapture = segment.tzAtCapture
        audioPath = segment.audioPath
        if let maxChars, maxChars > 0, let full = segment.text, full.count > maxChars {
            text = String(full.prefix(maxChars))
        } else {
            text = segment.text
        }
    }
}

/// Coarse activity bucket for `list_activity` (02 §2.5.4).
struct AgentActivityBucketDTO: Codable, Equatable, Sendable {
    var bucketStartMs: Int64
    var bucketEndMs: Int64
    var bucketStartIso: String
    var bucketEndIso: String
    var segmentCount: Int
    var speechCount: Int
    var musicCount: Int
    var otherCount: Int
    /// `"mic"` / `"system"` for per-track density; `null` = hour total when `include_total`.
    var track: String?

    enum CodingKeys: String, CodingKey {
        case bucketStartMs = "bucket_start_ms"
        case bucketEndMs = "bucket_end_ms"
        case bucketStartIso = "bucket_start_iso"
        case bucketEndIso = "bucket_end_iso"
        case segmentCount = "segment_count"
        case speechCount = "speech_count"
        case musicCount = "music_count"
        case otherCount = "other_count"
        case track
    }
}

/// Gap-merged contiguous speech block metadata (02 §2.6). Not a summary.
struct AgentSpeechBlockDTO: Codable, Equatable, Sendable {
    var track: String
    var t0Ms: Int64
    var t1Ms: Int64
    var t0Iso: String
    var t1Iso: String
    var segmentCount: Int
    var speechChars: Int
    var segmentIds: [String]
    var gapMsUsed: Int
    var tzAtCapture: String?

    enum CodingKeys: String, CodingKey {
        case track
        case t0Ms = "t0_ms"
        case t1Ms = "t1_ms"
        case t0Iso = "t0_iso"
        case t1Iso = "t1_iso"
        case segmentCount = "segment_count"
        case speechChars = "speech_chars"
        case segmentIds = "segment_ids"
        case gapMsUsed = "gap_ms_used"
        case tzAtCapture = "tz_at_capture"
    }
}

/// Derived wall-clock helpers for Agent IO DTOs (02 §3.2). Never written to SQLite.
enum AgentIOTime {
    /// ISO-8601 with millis + numeric offset (e.g. `2024-10-29T10:02:00.000+08:00`).
    static func iso8601(epochMs: Int64, timeZoneIdentifier: String?) -> String {
        let tz: TimeZone
        if let id = timeZoneIdentifier, let parsed = TimeZone(identifier: id) {
            tz = parsed
        } else {
            tz = .current
        }
        let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000.0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = tz
        return formatter.string(from: date)
    }
}

/// Centralized pagination / scan caps (02 §2.9).
enum AgentIOLimits {
    static let pageSize = 50
    static let hardLimit = 500
    static let defaultSpeechBlockGapMs = 120_000
}
