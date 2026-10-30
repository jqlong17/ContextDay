import Foundation

/// Spec §3.3.4 merge helpers (same track, overlap or gap ≤ merge_gap_ms; near-window dedupe).
enum SegmentMerger {
    /// Soft caps so runaway re-emits cannot blow up a single row (Spec v0.3.23).
    static let maxSourceSegmentIds = 32
    static let maxMergedTextChars = 8_000
    /// Both endpoints within this → treat as the same utterance window.
    static let nearDuplicateEndpointSlopMs: Int64 = 500
    /// Overlap / min(duration) ≥ this ratio (percent) → near-duplicate window.
    static let nearDuplicateMinOverlapPercent: Int64 = 80

    /// Signed gap from `previous` end to `incoming` start (negative when they overlap
    /// or `incoming` starts before `previous` ends). Prefer `separationMs` for eligibility.
    static func rawGapMs(previous: Segment, incoming: Segment) -> Int64 {
        incoming.t0Ms - previous.t1Ms
    }

    /// Non-overlapping distance between intervals; 0 when they overlap or touch.
    static func separationMs(previous: Segment, incoming: Segment) -> Int64 {
        if previous.t1Ms < incoming.t0Ms { return incoming.t0Ms - previous.t1Ms }
        if incoming.t1Ms < previous.t0Ms { return previous.t0Ms - incoming.t1Ms }
        return 0
    }

    static func overlapMs(a: Segment, b: Segment) -> Int64 {
        max(0, min(a.t1Ms, b.t1Ms) - max(a.t0Ms, b.t0Ms))
    }

    /// True when two same-track windows are essentially the same utterance
    /// (high overlap or both endpoints within slop) — fold without concatenating ASR text.
    static func isNearDuplicateWindow(previous: Segment, incoming: Segment) -> Bool {
        guard previous.track == incoming.track else { return false }
        let slop = nearDuplicateEndpointSlopMs
        if abs(previous.t0Ms - incoming.t0Ms) <= slop && abs(previous.t1Ms - incoming.t1Ms) <= slop {
            return true
        }
        let overlap = overlapMs(a: previous, b: incoming)
        let minDur = min(previous.t1Ms - previous.t0Ms, incoming.t1Ms - incoming.t0Ms)
        guard minDur > 0 else { return false }
        return overlap * 100 / minDur >= nearDuplicateMinOverlapPercent
    }

    /// Wall-clock near-dup check for VAD emission single-flight (same thresholds).
    static func isNearDuplicateInterval(a0: Int64, a1: Int64, b0: Int64, b1: Int64) -> Bool {
        let slop = nearDuplicateEndpointSlopMs
        if abs(a0 - b0) <= slop && abs(a1 - b1) <= slop { return true }
        let overlap = max(0, min(a1, b1) - max(a0, b0))
        let minDur = min(a1 - a0, b1 - b0)
        guard minDur > 0 else { return false }
        return overlap * 100 / minDur >= nearDuplicateMinOverlapPercent
    }

    /// If `incoming` should merge into `previous`, returns the merged row; else nil.
    static func mergedIfNeeded(
        previous: Segment,
        incoming: Segment,
        mergeGapMs: Int
    ) -> Segment? {
        guard previous.track == incoming.track else { return nil }
        guard separationMs(previous: previous, incoming: incoming) <= Int64(mergeGapMs) else {
            return nil
        }

        let nearDup = isNearDuplicateWindow(previous: previous, incoming: incoming)

        var out = previous
        out.t0Ms = min(previous.t0Ms, incoming.t0Ms)
        out.t1Ms = max(previous.t1Ms, incoming.t1Ms)
        if nearDup {
            out.text = pickNearDuplicateText(previous.text, incoming.text)
        } else {
            // Time-order concatenate for adjacent (non-duplicate) fragments.
            if previous.t0Ms <= incoming.t0Ms {
                out.text = concatenateText(previous.text, incoming.text)
            } else {
                out.text = concatenateText(incoming.text, previous.text)
            }
        }
        out.text = cappedText(out.text)
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
        out.sourceSegmentIds = Array(sources.prefix(maxSourceSegmentIds))
        out.mergedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        out.mergeGapMs = mergeGapMs
        // ASR metadata: last (latest by t1) non-empty.
        if incoming.t1Ms >= previous.t1Ms {
            out.asrModelId = incoming.asrModelId ?? previous.asrModelId
            out.asrModelVersion = incoming.asrModelVersion ?? previous.asrModelVersion
        } else {
            out.asrModelId = previous.asrModelId ?? incoming.asrModelId
            out.asrModelVersion = previous.asrModelVersion ?? incoming.asrModelVersion
        }
        if out.tzAtCapture == nil {
            out.tzAtCapture = incoming.tzAtCapture
        }
        return out
    }

    /// Prefer longer non-empty transcript; do not concatenate near-duplicate ASR noise.
    static func pickNearDuplicateText(_ a: String?, _ b: String?) -> String? {
        let left = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty && right.isEmpty { return nil }
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left.count >= right.count ? left : right
    }

    static func cappedText(_ text: String?) -> String? {
        guard let text else { return nil }
        if text.count <= maxMergedTextChars { return text }
        let idx = text.index(text.startIndex, offsetBy: maxMergedTextChars)
        return String(text[..<idx])
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
