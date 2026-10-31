import Foundation

/// A/B PCM capture-buffer variant (Spec §3.2.1 / v0.3.29).
enum PCMBufferVariant: String, Codable, Sendable, CaseIterable {
    /// Control: legacy ~10 min soft-cap (growable `Data`).
    case a = "A"
    /// Treatment: fixed-capacity ring ≈ 60s @16k Int16 (product default after green A/B).
    case b = "B"
}

/// Resolves PCM buffer capacity for dual-track capture.
///
/// **Variant B = 60s** (not 45): `maxSpeech` 30 + gate ~5 + `silenceEnd` ~2
/// + process tick / pending-tail ~2 + ASR/snapshot lag margin ~21 ≈ **60**.
/// Upper end of the 45–60s band so a forced 30s utterance plus gate window always fits.
enum PCMBufferPolicy {
    static let variantASeconds = 600
    static let variantBSeconds = 60

    static let variantDefaultsKey = "pcm_buffer_variant"
    static let secondsDefaultsKey = "pcm_buffer_seconds"

    /// Product default after this change: B. Rollback → `defaults write … pcm_buffer_variant A`.
    static var defaultVariant: PCMBufferVariant { .b }

    /// Compile-time: `-DCONTEXTDAY_PCM_VARIANT_A` or `-DCONTEXTDAY_PCM_VARIANT_B` in OTHER_SWIFT_FLAGS.
    static var compileTimeOverride: PCMBufferVariant? {
        #if CONTEXTDAY_PCM_VARIANT_A
        return .a
        #elseif CONTEXTDAY_PCM_VARIANT_B
        return .b
        #else
        return nil
        #endif
    }

    static func resolveVariant(
        defaults: UserDefaults = .standard
    ) -> PCMBufferVariant {
        if let compile = compileTimeOverride {
            return compile
        }
        if let raw = defaults.string(forKey: variantDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           let parsed = PCMBufferVariant(rawValue: raw) {
            return parsed
        }
        // Alternate key: absolute seconds. ≥300 → A (legacy), (0,300) → B.
        if defaults.object(forKey: secondsDefaultsKey) != nil {
            let sec = defaults.integer(forKey: secondsDefaultsKey)
            if sec >= variantASeconds / 2 { return .a }
            if sec > 0 { return .b }
        }
        return defaultVariant
    }

    static func capacitySeconds(for variant: PCMBufferVariant) -> Int {
        switch variant {
        case .a: return variantASeconds
        case .b: return variantBSeconds
        }
    }

    static func capacityBytes(sampleRate: Int, variant: PCMBufferVariant) -> Int {
        let sr = max(1, sampleRate)
        return sr * 2 * capacitySeconds(for: variant)
    }

    /// B uses a preallocated fixed ring; A keeps growable soft-cap semantics.
    static func usesFixedRing(_ variant: PCMBufferVariant) -> Bool {
        variant == .b
    }
}

/// Point-in-time buffer metrics for A/B measurement harness (logs / XCTest).
struct PCMBufferMetrics: Equatable, Sendable {
    var variant: String
    var sampleRate: Int
    var filledBytes: Int
    var capacityBytes: Int
    var peakFilledBytes: Int
    var streamStartMs: Int64

    var filledSeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(filledBytes / 2) / Double(sampleRate)
    }

    var capacitySeconds: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(capacityBytes / 2) / Double(sampleRate)
    }

    var logLine: String {
        String(
            format: "pcm_buf variant=%@ filledBytes=%d capacityBytes=%d peakBytes=%d filledSec=%.1f capSec=%.0f streamStartMs=%lld",
            variant, filledBytes, capacityBytes, peakFilledBytes, filledSeconds, capacitySeconds, streamStartMs
        )
    }
}
