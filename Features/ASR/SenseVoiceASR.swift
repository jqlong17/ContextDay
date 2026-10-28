import Foundation

/// SenseVoice Core ML int8 — primary ASR path (Spec §1.4 / §3.1).
/// Phase 0 stub: do **not** load Core ML or fall back to ONNX silently.
final class SenseVoiceASR {
    struct Transcript {
        var text: String
        var modelId: String
        var modelVersion: String?
    }

    private(set) var isModelLoaded = false

    func loadModelIfNeeded() throws {
        // TODO(Phase 2): load bundled SenseVoice Core ML int8.
        // On failure: surface error; never silently switch to ONNX (Spec §3.5).
        isModelLoaded = false
        throw ASRError.notImplemented
    }

    func transcribe(pcm16kMono _: Data) throws -> Transcript {
        // TODO(Phase 2): run Core ML inference; return text + model metadata for Segment.
        throw ASRError.notImplemented
    }

    enum ASRError: Error, LocalizedError {
        case notImplemented
        case modelLoadFailed(String)

        var errorDescription: String? {
            switch self {
            case .notImplemented:
                return "SenseVoice Core ML not wired in Phase 0"
            case .modelLoadFailed(let detail):
                return "SenseVoice Core ML load failed: \(detail)"
            }
        }
    }
}
