import Foundation

/// Track for dual-rail capture (Spec §3.3.3).
enum SegmentTrack: String, Codable, Sendable {
    case mic
    case system
}

/// YAMNet gate label (Spec §3.3.2). Music preferred when tied with Speech.
enum GateLabel: String, Codable, Sendable {
    case speech
    case music
    case other
}

/// Timeline row — sole transcription authority lives in SQLite (Spec §3.3.3).
struct Segment: Identifiable, Codable, Sendable {
    var id: UUID
    var track: SegmentTrack
    var t0Ms: Int64
    var t1Ms: Int64
    var tzAtCapture: String?
    var text: String?
    var gateLabel: GateLabel?
    /// Path relative to Application Support root, e.g. `audio/2026-10-28/mic/<uuid>.opus`.
    var audioPath: String?
    var sourceSegmentIds: [UUID]
    var createdAtMs: Int64
    var mergedAtMs: Int64?
    var mergeGapMs: Int?
    var asrModelId: String?
    var asrModelVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case track
        case t0Ms = "t0_ms"
        case t1Ms = "t1_ms"
        case tzAtCapture = "tz_at_capture"
        case text
        case gateLabel = "gate_label"
        case audioPath = "audio_path"
        case sourceSegmentIds = "source_segment_ids"
        case createdAtMs = "created_at_ms"
        case mergedAtMs = "merged_at_ms"
        case mergeGapMs = "merge_gap_ms"
        case asrModelId = "asr_model_id"
        case asrModelVersion = "asr_model_version"
    }
}
