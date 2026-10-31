import Foundation

/// Weak registry so Agent IO can reach the live `CapturePipeline` owned by DesktopControl.
/// Debug / CI only — not a second capture stack.
enum CaptureInjectHost {
    private static let lock = NSLock()
    private static weak var pipeline: CapturePipeline?

    static func register(_ pipeline: CapturePipeline) {
        lock.lock()
        self.pipeline = pipeline
        lock.unlock()
    }

    static func current() -> CapturePipeline? {
        lock.lock()
        defer { lock.unlock() }
        return pipeline
    }
}
