import AppKit
import AVFoundation
import CoreGraphics
import ImageIO

/// Twin-eye 3D orb: idle still + one-shot eye-click movie (Spec §2.7).
final class DesktopOrbView: NSView {
    private let idleLayer = CALayer()
    private let playerView = NSView()
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: ((NSPoint) -> Void)?

    /// Must be false so AppKit composites clear/orb alpha instead of an opaque plate.
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        setupIdle()
        setupPlayerHost()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    private func setupIdle() {
        // Draw via CALayer.contents (not NSImageView / not NSImage(named:)) so
        // Assets.car cannot win and alpha is respected.
        idleLayer.contentsGravity = .resizeAspect
        idleLayer.backgroundColor = NSColor.clear.cgColor
        idleLayer.isOpaque = false
        idleLayer.frame = bounds
        idleLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(idleLayer)

        if let image = Self.loadKeyedIdleImage() {
            idleLayer.contents = image
        } else {
            NSLog("ContextDay: keyed idle.png not found — DesktopOrb corners may be wrong")
        }
    }

    /// Bundle `DesktopOrb/idle.png` only, then hard chroma-key lime/green plate → alpha 0.
    private static func loadKeyedIdleImage() -> CGImage? {
        let url =
            Bundle.main.url(forResource: "idle", withExtension: "png", subdirectory: "DesktopOrb")
            ?? Bundle.main.url(forResource: "idle", withExtension: "png")
        guard let url else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return chromaKeyGreenPlate(cgImage)
    }

    /// Runtime hard key: edge-connected green / near-transparent → true alpha 0.
    private static func chromaKeyGreenPlate(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isBackground(_ i: Int) -> Bool {
            let r = Int(pixels[i])
            let g = Int(pixels[i + 1])
            let b = Int(pixels[i + 2])
            let a = Int(pixels[i + 3])
            if a < 200 { return true }
            // Lime / chroma plate (covers #00FF00-ish and spill)
            if g > 40 && g > r + 15 && g > b + 15 && (g - max(r, b)) > 12 {
                return true
            }
            return false
        }

        var bg = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * 4)

        func enqueue(_ x: Int, _ y: Int) {
            let idx = y * width + x
            if bg[idx] { return }
            let pi = idx * 4
            guard isBackground(pi) else { return }
            bg[idx] = true
            queue.append(idx)
        }

        for x in 0..<width {
            enqueue(x, 0)
            enqueue(x, height - 1)
        }
        for y in 0..<height {
            enqueue(0, y)
            enqueue(width - 1, y)
        }

        var qi = 0
        while qi < queue.count {
            let idx = queue[qi]; qi += 1
            let x = idx % width
            let y = idx / width
            if x > 0 { enqueue(x - 1, y) }
            if x + 1 < width { enqueue(x + 1, y) }
            if y > 0 { enqueue(x, y - 1) }
            if y + 1 < height { enqueue(x, y + 1) }
        }

        for idx in 0..<(width * height) where bg[idx] {
            let pi = idx * 4
            pixels[pi] = 0
            pixels[pi + 1] = 0
            pixels[pi + 2] = 0
            pixels[pi + 3] = 0
        }

        // Soft fringe: punch residual green next to keyed bg
        for idx in 0..<(width * height) where !bg[idx] {
            let x = idx % width
            let y = idx / width
            var nearBG = false
            for dy in -2...2 {
                for dx in -2...2 {
                    let nx = x + dx
                    let ny = y + dy
                    if nx >= 0, nx < width, ny >= 0, ny < height, bg[ny * width + nx] {
                        nearBG = true
                        break
                    }
                }
                if nearBG { break }
            }
            guard nearBG else { continue }
            let pi = idx * 4
            let r = Int(pixels[pi])
            let g = Int(pixels[pi + 1])
            let b = Int(pixels[pi + 2])
            if g > r + 10 && g > b + 10 {
                pixels[pi] = 0
                pixels[pi + 1] = 0
                pixels[pi + 2] = 0
                pixels[pi + 3] = 0
            }
        }

        guard let keyed = ctx.makeImage() else { return image }
        return keyed
    }

    private func setupPlayerHost() {
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        playerView.layer?.isOpaque = false
        playerView.frame = bounds
        playerView.autoresizingMask = [.width, .height]
        playerView.isHidden = true
        addSubview(playerView)
    }

    /// Plays `eye-click-2s.mp4` once, then settles back to idle (first≈last frame).
    /// Note: mp4 still has greenscreen — rematte is a follow-up; idle path is keyed.
    func playEyeClickOnce() {
        guard let url = Self.eyeClickURL() else {
            NSLog("ContextDay: eye-click-2s.mp4 not found in bundle")
            return
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause

        let layer = AVPlayerLayer(player: avPlayer)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.clear.cgColor
        layer.isOpaque = false
        layer.frame = playerView.bounds
        playerView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        playerView.layer?.addSublayer(layer)
        // Keep idleLayer visible underneath so end-of-clip teardown cannot blink/vanish the orb.
        idleLayer.isHidden = false
        playerView.isHidden = false

        player = avPlayer
        playerLayer = layer

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.settleToIdle()
        }

        avPlayer.seek(to: .zero)
        avPlayer.play()
    }

    private func settleToIdle() {
        // Prefer holding the last AVPlayer frame (clip first≈last) so settle color-matches
        // the eye-click end instead of snapping to keyed idle (flicker / plate mismatch).
        idleLayer.isHidden = false
        playerView.isHidden = false
        player?.pause()
        if let item = player?.currentItem {
            let end = item.duration
            if end.isNumeric, end.isValid, !end.isIndefinite, end.seconds > 0 {
                player?.seek(to: end, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        // Keep player + layer alive paused on the end frame until the next playEyeClickOnce.
    }

    private static func eyeClickURL() -> URL? {
        // Prefer rematted .mov when present; fall back to greenscreen .mp4.
        let names = [("eye-click-2s", "mov"), ("eye-click-2s", "mp4")]
        for (name, ext) in names {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "DesktopOrb") {
                return url
            }
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    override func layout() {
        super.layout()
        // Sync layer frames without implicit CA actions so window-driven resize
        // (NSAnimationContext ease-in-out) stays smooth and settle/idle don't lag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        idleLayer.frame = bounds
        playerLayer?.frame = playerView.bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown {
            onPrimaryClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onSecondaryClick?(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
