import AppKit
import ImageIO
import QuartzCore

/// Seamless PNG frame-loop player (首尾针): loads `fNN.png` from a Bundle subdirectory
/// and advances on a Timer. Used for sleep idle; ready/other loops can reuse the same API.
final class OrbFrameLoopPlayer {
    private weak var layer: CALayer?
    private var frames: [CGImage] = []
    private var timer: Timer?
    private var index = 0
    private(set) var isRunning = false

    /// Frames per second for the loop (sleep breathe ~8–12).
    var framesPerSecond: Double = 10

    var frameCount: Int { frames.count }

    /// Load zero-padded `f*.png` from Bundle `DesktopOrb/<subdirectory>/`.
    /// Returns false when fewer than 2 frames (caller should fall back).
    @discardableResult
    func loadFromBundle(subdirectory: String) -> Bool {
        stop()
        frames = Self.loadFrames(subdirectory: subdirectory)
        index = 0
        return frames.count >= 2
    }

    /// Assign frames from an already-keyed image list (tests / custom pipelines).
    func setFrames(_ images: [CGImage]) {
        stop()
        frames = images
        index = 0
    }

    func start(on layer: CALayer) {
        stopTimerOnly()
        self.layer = layer
        guard frames.count >= 2 else { return }
        isRunning = true
        index = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = frames[0]
        CATransaction.commit()

        let interval = max(1.0 / 30.0, 1.0 / max(1.0, framesPerSecond))
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        stopTimerOnly()
        isRunning = false
        layer = nil
    }

    private func stopTimerOnly() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isRunning, frames.count >= 2, let layer else { return }
        index = (index + 1) % frames.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = frames[index]
        CATransaction.commit()
    }

    private static func loadFrames(subdirectory: String) -> [CGImage] {
        let folder =
            Bundle.main.url(forResource: subdirectory, withExtension: nil, subdirectory: "DesktopOrb")
            ?? Bundle.main.resourceURL?
                .appendingPathComponent("DesktopOrb", isDirectory: true)
                .appendingPathComponent(subdirectory, isDirectory: true)

        guard let folder else { return [] }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return [] }
        let pngs = names
            .filter { $0.lowercased().hasPrefix("f") && $0.lowercased().hasSuffix(".png") }
            .sorted()
        var images: [CGImage] = []
        images.reserveCapacity(pngs.count)
        for name in pngs {
            let url = folder.appendingPathComponent(name)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continue
            }
            images.append(cg)
        }
        return images
    }
}
