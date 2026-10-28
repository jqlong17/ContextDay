import Foundation

/// JSON-friendly Segment projection for Agent IO (§2.9). snake_case keys.
struct AgentSegmentDTO: Codable, Equatable, Sendable {
    var segmentId: String
    var t0Ms: Int64
    var t1Ms: Int64
    var track: String
    var gateLabel: String?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case segmentId = "segment_id"
        case t0Ms = "t0_ms"
        case t1Ms = "t1_ms"
        case track
        case gateLabel = "gate_label"
        case text
    }

    init(segment: Segment, maxChars: Int? = nil) {
        segmentId = segment.id.uuidString.lowercased()
        t0Ms = segment.t0Ms
        t1Ms = segment.t1Ms
        track = segment.track.rawValue
        gateLabel = segment.gateLabel?.rawValue
        if let maxChars, maxChars > 0, let full = segment.text, full.count > maxChars {
            text = String(full.prefix(maxChars))
        } else {
            text = segment.text
        }
    }
}

/// Coarse activity bucket for `list_activity` (§2.9).
struct AgentActivityBucketDTO: Codable, Equatable, Sendable {
    var bucketStartMs: Int64
    var bucketEndMs: Int64
    var segmentCount: Int
    var track: String?

    enum CodingKeys: String, CodingKey {
        case bucketStartMs = "bucket_start_ms"
        case bucketEndMs = "bucket_end_ms"
        case segmentCount = "segment_count"
        case track
    }
}
