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
    }

    var gateEnabled: Bool
    var keepAudio: Bool
    var audioScope: AudioScope
    var audioQuality: AudioQuality
    var mergeGapMs: Int
    /// `nil` = no automatic retention purge (manual clear still available).
    var retentionDays: Int?

    static let `default` = AppConfig(
        gateEnabled: true,
        keepAudio: false,
        audioScope: .speechOnly,
        audioQuality: .opus24,
        mergeGapMs: 2_000,
        retentionDays: 30
    )

    /// Approximate GB/day for full-day keep-audio (Spec §2.4); UI copy later.
    var estimatedKeepAudioGBPerDay: Double {
        switch audioQuality {
        case .opus12: return 0.13
        case .opus24: return 0.26
        case .opus64: return 0.7
        }
    }
}

/// Thin UserDefaults suite wrapper — Phase 0 stub (no Settings UI yet).
enum AppConfigStore {
    static let suiteName = "app.contextday"

    private static var suite: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func load() -> AppConfig {
        // TODO(Phase 2): round-trip each field; enforce gate_enabled=false → audio_scope=all.
        _ = suite
        return .default
    }

    static func save(_ config: AppConfig) {
        // TODO(Phase 2): persist to suite.
        _ = config
    }
}
