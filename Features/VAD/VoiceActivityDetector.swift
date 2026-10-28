import Foundation

/// VAD segmentation: silence end ~1.5–2s; min 3s / max 30s (Spec §2.2).
/// Separate from store merge gap. Phase 0 stub only.
final class VoiceActivityDetector {
    var minSpeechMs: Int = 3_000
    var maxSpeechMs: Int = 30_000
    var silenceEndMs: Int = 1_750

    struct Utterance {
        var t0Ms: Int64
        var t1Ms: Int64
    }

    /// Placeholder — returns no utterances until real VAD lands.
    func segment(pcm _: Data, streamStartMs _: Int64) -> [Utterance] {
        // TODO(Phase 2): energy / WebRTC-style VAD on ring-buffer slices.
        []
    }
}
