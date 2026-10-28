import AppKit
import AVFoundation

/// Twin-eye 3D orb: idle still + one-shot eye-click movie (Spec §2.7).
final class DesktopOrbView: NSView {
    private let idleImageView = NSImageView()
    private let playerView = NSView()
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?

    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: ((NSPoint) -> Void)?

    /// Must be false so AppKit composites the clear/orb alpha instead of filling an opaque plate.
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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
        idleImageView.imageScaling = .scaleProportionallyUpOrDown
        idleImageView.imageAlignment = .alignCenter
        idleImageView.wantsLayer = true
        idleImageView.layer?.backgroundColor = NSColor.clear.cgColor
        // Do NOT use NSImage(named: "DesktopOrbIdle") — Assets.car can keep a stale
        // greenscreen plate. Always load the keyed Bundle file under DesktopOrb/.
        if let url = Bundle.main.url(forResource: "idle", withExtension: "png", subdirectory: "DesktopOrb"),
           let image = NSImage(contentsOf: url) {
            idleImageView.image = image
        } else if let url = Bundle.main.url(forResource: "idle", withExtension: "png"),
                  let image = NSImage(contentsOf: url) {
            // Flattened-copy fallback if folder reference packaging differs.
            idleImageView.image = image
            NSLog("ContextDay: loaded idle.png without DesktopOrb/ subdirectory")
        } else {
            NSLog("ContextDay: idle.png not found in bundle (DesktopOrb/)")
        }
        idleImageView.frame = bounds
        idleImageView.autoresizingMask = [.width, .height]
        addSubview(idleImageView)
    }

    private func setupPlayerHost() {
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        playerView.frame = bounds
        playerView.autoresizingMask = [.width, .height]
        playerView.isHidden = true
        addSubview(playerView)
    }

    /// Plays `eye-click-2s.mp4` once, then settles back to idle (first≈last frame).
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
        layer.frame = playerView.bounds
        playerView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        playerView.layer?.addSublayer(layer)
        playerView.isHidden = false
        idleImageView.isHidden = true

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
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        playerView.isHidden = true
        idleImageView.isHidden = false
    }

    private static func eyeClickURL() -> URL? {
        if let url = Bundle.main.url(forResource: "eye-click-2s", withExtension: "mp4", subdirectory: "DesktopOrb") {
            return url
        }
        return Bundle.main.url(forResource: "eye-click-2s", withExtension: "mp4")
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
