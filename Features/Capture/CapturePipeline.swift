import Foundation

/// Dual-rail capture → RAM ring buffer (Spec §3.1 Capture).
/// Phase 0 stub — real AVAudioEngine mic + ScreenCaptureKit system audio in Phase 1.
final class CapturePipeline {
    enum Track {
        case mic
        case system
    }

    private(set) var isRunning = false

    func start() {
        // TODO(Phase 1): request mic / screen-recording entitlements; start engines; fill ring buffer.
        isRunning = true
        NSLog("ContextDay CapturePipeline: start() stub — no PCM yet")
    }

    func stop() {
        // TODO(Phase 1): tear down engines; keep ring buffer drain policy.
        isRunning = false
        NSLog("ContextDay CapturePipeline: stop() stub")
    }
}
