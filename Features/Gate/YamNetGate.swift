import Foundation

/// YAMNet-ONNX ~5s window gate; dual-rail labels; Music > Speech when tied (Spec §1.4 / §3.1).
/// Phase 0 stub — do not load ONNX yet.
final class YamNetGate {
    struct LabelResult {
        var track: SegmentTrack
        var label: GateLabel
        var windowStartMs: Int64
        var windowEndMs: Int64
    }

    /// Placeholder: always returns `.other` until model is wired.
    func classify(track: SegmentTrack, pcmWindow _: Data, windowStartMs: Int64, windowEndMs: Int64) -> LabelResult {
        // TODO(Phase 1): run YAMNet-ONNX on 16 kHz mono window; apply Music-preferred bias.
        LabelResult(track: track, label: .other, windowStartMs: windowStartMs, windowEndMs: windowEndMs)
    }
}
