import CoreGraphics
import Foundation

/// UserDefaults preference snapshot (Spec §3.3.5). Not stored in SQLite.
struct AppConfig: Equatable, Sendable {
    enum AudioScope: String, Codable, Sendable {
        case speechOnly = "speech_only"
        case all
    }

    /// User-visible keep-audio quality presets — Opus only (no WAV/PCM).
    enum AudioQuality: String, Codable, Sendable {
        case opus12 = "opus_12"
        case opus24 = "opus_24"
        case opus64 = "opus_64"

        var bitrate: Int {
            switch self {
            case .opus12: return 12_000
            case .opus24: return 24_000
            case .opus64: return 64_000
            }
        }
    }

    var gateEnabled: Bool
    var keepAudio: Bool
    var audioScope: AudioScope
    var audioQuality: AudioQuality
    var mergeGapMs: Int
    /// `nil` = no automatic retention purge (manual clear still available).
    var retentionDays: Int?
    /// Capture system audio via ScreenCaptureKit when true.
    var captureSystemAudio: Bool
    /// Open at login via `SMAppService.mainApp` (Spec §2.2). Default ON; user can turn off (App Store).
    var openAtLogin: Bool

    static let `default` = AppConfig(
        gateEnabled: true,
        keepAudio: false,
        audioScope: .speechOnly,
        audioQuality: .opus24,
        mergeGapMs: 2_000,
        retentionDays: 30,
        captureSystemAudio: true,
        openAtLogin: true
    )

    /// Approximate GB/day for full-day keep-audio (Spec §2.4).
    var estimatedKeepAudioGBPerDay: Double {
        switch audioQuality {
        case .opus12: return 0.13
        case .opus24: return 0.26
        case .opus64: return 0.7
        }
    }

    /// `gate_enabled=false` forces audio scope to all (Spec §2.2).
    mutating func normalize() {
        if !gateEnabled {
            audioScope = .all
        }
        mergeGapMs = min(3_000, max(1_000, mergeGapMs))
        if let days = retentionDays, days < 1 {
            retentionDays = 1
        }
    }
}

/// UserDefaults persistence for `AppConfig`.
enum AppConfigStore {
    static let suiteName = "app.contextday"

    private enum Key {
        static let gateEnabled = "gate_enabled"
        static let keepAudio = "keep_audio"
        static let audioScope = "audio_scope"
        static let audioQuality = "audio_quality"
        static let mergeGapMs = "merge_gap_ms"
        static let retentionDays = "retention_days"
        static let captureSystemAudio = "capture_system_audio"
        static let openAtLogin = "open_at_login"
        static let retentionNil = "retention_days_is_nil"
    }

    private static var defaults: UserDefaults { .standard }

    static func load() -> AppConfig {
        let d = defaults
        var cfg = AppConfig.default
        if d.object(forKey: Key.gateEnabled) != nil {
            cfg.gateEnabled = d.bool(forKey: Key.gateEnabled)
        }
        if d.object(forKey: Key.keepAudio) != nil {
            cfg.keepAudio = d.bool(forKey: Key.keepAudio)
        }
        if let scope = d.string(forKey: Key.audioScope),
           let parsed = AppConfig.AudioScope(rawValue: scope) {
            cfg.audioScope = parsed
        }
        if let quality = d.string(forKey: Key.audioQuality),
           let parsed = AppConfig.AudioQuality(rawValue: quality) {
            cfg.audioQuality = parsed
        }
        if d.object(forKey: Key.mergeGapMs) != nil {
            cfg.mergeGapMs = d.integer(forKey: Key.mergeGapMs)
        }
        if d.bool(forKey: Key.retentionNil) {
            cfg.retentionDays = nil
        } else if d.object(forKey: Key.retentionDays) != nil {
            cfg.retentionDays = d.integer(forKey: Key.retentionDays)
        }
        if d.object(forKey: Key.captureSystemAudio) != nil {
            cfg.captureSystemAudio = d.bool(forKey: Key.captureSystemAudio)
        }
        if d.object(forKey: Key.openAtLogin) != nil {
            cfg.openAtLogin = d.bool(forKey: Key.openAtLogin)
        }
        cfg.normalize()
        return cfg
    }

    static func save(_ config: AppConfig) {
        var cfg = config
        cfg.normalize()
        let d = defaults
        d.set(cfg.gateEnabled, forKey: Key.gateEnabled)
        d.set(cfg.keepAudio, forKey: Key.keepAudio)
        d.set(cfg.audioScope.rawValue, forKey: Key.audioScope)
        d.set(cfg.audioQuality.rawValue, forKey: Key.audioQuality)
        d.set(cfg.mergeGapMs, forKey: Key.mergeGapMs)
        if let days = cfg.retentionDays {
            d.set(false, forKey: Key.retentionNil)
            d.set(days, forKey: Key.retentionDays)
        } else {
            d.set(true, forKey: Key.retentionNil)
            d.removeObject(forKey: Key.retentionDays)
        }
        d.set(cfg.captureSystemAudio, forKey: Key.captureSystemAudio)
        d.set(cfg.openAtLogin, forKey: Key.openAtLogin)
    }
}

/// Desktop orb size preference (pt). Default 64 ≈ Finder icon width.
enum OrbSizeStore {
    static let key = "orbSizePt"
    static let allowed: [CGFloat] = [48, 64, 80, 96, 128]
    static let `default`: CGFloat = 64

    static func load() -> CGFloat {
        let v = UserDefaults.standard.object(forKey: key) as? Double
        let pt = CGFloat(v ?? Double(Self.default))
        return allowed.contains(pt) ? pt : Self.default
    }

    static func save(_ pt: CGFloat) {
        let value = allowed.contains(pt) ? pt : Self.default
        UserDefaults.standard.set(Double(value), forKey: key)
    }
}
