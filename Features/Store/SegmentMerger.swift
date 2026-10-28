import Foundation

/// Spec §3.3.4 merge helpers (same track, gap ≤ merge_gap_ms).
enum SegmentMerger {
    /// If `incoming` should merge into `previous`, returns the merged row; else nil.
    static func mergedIfNeeded(
        previous: Segment,
        incoming: Segment,
        mergeGapMs: Int
    ) -> Segment? {
        guard previous.track == incoming.track else { return nil }
        guard incoming.t0Ms >= previous.t0Ms else { return nil }
        let gap = incoming.t0Ms - previous.t1Ms
        guard gap <= Int64(mergeGapMs) else { return nil }

        var out = previous
        out.t0Ms = min(previous.t0Ms, incoming.t0Ms)
        out.t1Ms = max(previous.t1Ms, incoming.t1Ms)
        out.text = concatenateText(previous.text, incoming.text)
        out.gateLabel = pickGateLabel(previous: previous, incoming: incoming)
        // Keep earliest audio file (by t0).
        if let pAudio = previous.audioPath, let iAudio = incoming.audioPath {
            out.audioPath = previous.t0Ms <= incoming.t0Ms ? pAudio : iAudio
        } else {
            out.audioPath = previous.audioPath ?? incoming.audioPath
        }
        var sources = Set(previous.sourceSegmentIds)
        if sources.isEmpty { sources.insert(previous.id) }
        var incomingSources = Set(incoming.sourceSegmentIds)
        if incomingSources.isEmpty { incomingSources.insert(incoming.id) }
        sources.formUnion(incomingSources)
        out.sourceSegmentIds = Array(sources)
        out.mergedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        out.mergeGapMs = mergeGapMs
        // ASR metadata: last (latest) non-empty.
        out.asrModelId = incoming.asrModelId ?? previous.asrModelId
        out.asrModelVersion = incoming.asrModelVersion ?? previous.asrModelVersion
        if out.tzAtCapture == nil {
            out.tzAtCapture = incoming.tzAtCapture
        }
        return out
    }

    static func concatenateText(_ a: String?, _ b: String?) -> String? {
        let left = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty && right.isEmpty { return nil }
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        // Spec: 段间不加空格/换行
        return left + right
    }

    /// Longest duration wins; ties prefer speech > music > other.
    static func pickGateLabel(previous: Segment, incoming: Segment) -> GateLabel? {
        let prevDur = previous.t1Ms - previous.t0Ms
        let inDur = incoming.t1Ms - incoming.t0Ms
        if prevDur > inDur { return previous.gateLabel ?? incoming.gateLabel }
        if inDur > prevDur { return incoming.gateLabel ?? previous.gateLabel }
        return preferred(previous.gateLabel, incoming.gateLabel)
    }

    private static func preferred(_ a: GateLabel?, _ b: GateLabel?) -> GateLabel? {
        let rank: (GateLabel?) -> Int = { label in
            switch label {
            case .some(.speech): return 3
            case .some(.music): return 2
            case .some(.other): return 1
            case .none: return 0
            }
        }
        return rank(a) >= rank(b) ? a : b
    }
}
