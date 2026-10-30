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

    /// Fired on left-button click (not drag). Controller may start recording when idle.
    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: ((NSPoint) -> Void)?

    private var mouseDownLocationInWindow: NSPoint?
    private var primaryDidDrag = false
    /// Movement beyond this (pt) counts as drag, not click — keep left-drag movable.
    private static let primaryClickSlop: CGFloat = 4

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

    /// Bundle `DesktopOrb/idle.png` only. Skip hard-key when corners are already transparent;
    /// otherwise chroma-key lime/green plate → alpha 0.
    private static func loadKeyedIdleImage() -> CGImage? {
        let url =
            Bundle.main.url(forResource: "idle", withExtension: "png", subdirectory: "DesktopOrb")
            ?? Bundle.main.url(forResource: "idle", withExtension: "png")
        guard let url else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        if cornersAlreadyTransparent(cgImage) {
            return cgImage
        }
        return chromaKeyGreenPlate(cgImage)
    }

    /// True when all four corners are already alpha≈0 (shipped idle.png) — no need to re-key.
    private static func cornersAlreadyTransparent(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        let points = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        for (x, y) in points {
            guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
                return false
            }
            var pixel = [UInt8](repeating: 0, count: 4)
            guard let ctx = CGContext(
                data: &pixel,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            if Int(pixel[3]) >= 16 { return false }
        }
        return true
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

    /// Plays rematted `eye-click-2s.mov` (ProRes 4444 / yuva) once, then settles to
    /// keyed `idle.png` (player torn down). Legacy greenscreen `.mp4` is never used.
    func playEyeClickOnce() {
        guard let url = Self.eyeClickURL() else {
            NSLog("ContextDay: eye-click-2s.mov not found in bundle (alpha rematte required)")
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
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        playerView.layer?.isOpaque = false
        playerView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        playerView.layer?.addSublayer(layer)
        // Keep idleLayer visible underneath so end-of-clip / settle never blinks the orb away.
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
        // Tear down AVPlayer and show keyed idle.png. Holding the rematted last frame
        // still left ~1% green fringe (soft rematte leftovers) in screenshot QA; idle
        // stays under the player during play, so hide+teardown snaps cleanly (greenish=0).
        idleLayer.isHidden = false
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        playerView.isHidden = true
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private static func eyeClickURL() -> URL? {
        // Alpha rematte only — never return the legacy greenscreen H.264 `.mp4`.
        if let url = Bundle.main.url(forResource: "eye-click-2s", withExtension: "mov", subdirectory: "DesktopOrb") {
            return url
        }
        return Bundle.main.url(forResource: "eye-click-2s", withExtension: "mov")
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
        // Track for click-vs-drag. Window drag still works via `isMovableByWindowBackground`.
        mouseDownLocationInWindow = event.locationInWindow
        primaryDidDrag = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = mouseDownLocationInWindow {
            let p = event.locationInWindow
            let dx = p.x - start.x
            let dy = p.y - start.y
            if (dx * dx + dy * dy) > (Self.primaryClickSlop * Self.primaryClickSlop) {
                primaryDidDrag = true
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocationInWindow = nil
            primaryDidDrag = false
            super.mouseUp(with: event)
        }
        guard event.type == .leftMouseUp else { return }
        guard !primaryDidDrag else { return }
        if let start = mouseDownLocationInWindow {
            let p = event.locationInWindow
            let dx = p.x - start.x
            let dy = p.y - start.y
            if (dx * dx + dy * dy) > (Self.primaryClickSlop * Self.primaryClickSlop) {
                return
            }
        }
        // Spec §2.7.3: idle/paused left-click starts recording (controller decides).
        onPrimaryClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onSecondaryClick?(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
