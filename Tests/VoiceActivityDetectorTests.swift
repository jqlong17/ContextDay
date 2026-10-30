import XCTest
@testable import ContextDay

final class VoiceActivityDetectorTests: XCTestCase {
    private let sampleRate = 16_000

    /// Silence spanning the max boundary, then voice again, must still cap ≤ max samples.
    func testTrailingSilenceDoesNotExceedMaxSpeechSamples() {
        let vad = makeVAD()
        let frameSamples = sampleRate * vad.frameMs / 1000
        let maxSamples = sampleRate * vad.maxSpeechMs / 1000 // 480_000
        // Voice 0..<990, silence 990..<1020 (crosses max=1000), voice 1020..<1035.
        // Pre-fix voiced cut used endFrame=f+1 → 1030+ frames (494400 samples).
        let totalFrames = 1_035
        var pcm = Data(count: totalFrames * frameSamples * 2)
        pcm.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let voiceAmp: Int16 = 8_000
            for f in 0..<totalFrames {
                let voiced = f < 990 || f >= 1_020
                if !voiced { continue }
                let base = f * frameSamples
                for i in 0..<frameSamples {
                    samples[base + i] = voiceAmp
                }
            }
        }

        let utterances = vad.segment(pcm: pcm, streamStartMs: 0, sampleRate: sampleRate)
        XCTAssertFalse(utterances.isEmpty, "expected at least one utterance")
        for utt in utterances {
            let len = utt.endSample - utt.startSample
            XCTAssertLessThanOrEqual(len, maxSamples, "utterance samples \(len) exceed max \(maxSamples)")
        }
    }

    /// Continuous voiced PCM longer than maxSpeechMs must force-emit (no silence required).
    func testContinuousVoicedForcesMaxSpeechCut() {
        let vad = makeVAD()
        let frameSamples = sampleRate * vad.frameMs / 1000
        let maxFrames = vad.maxSpeechMs / vad.frameMs // 1000
        let totalFrames = maxFrames + 200 // ~36s continuous voice
        let maxSamples = sampleRate * vad.maxSpeechMs / 1000

        // Amplitude ≈ 0.02 RMS — clearly above lowered absolute / adaptive floor.
        let pcm = synthesizePCM(
            frameCount: totalFrames,
            frameSamples: frameSamples,
            amp: 700,
            voiced: { _ in true }
        )

        let utterances = vad.segment(pcm: pcm, streamStartMs: 0, sampleRate: sampleRate)
        XCTAssertFalse(utterances.isEmpty, "continuous voice must force-cut at maxSpeechMs")
        XCTAssertGreaterThanOrEqual(utterances.count, 1)
        for utt in utterances {
            let len = utt.endSample - utt.startSample
            XCTAssertLessThanOrEqual(len, maxSamples)
            XCTAssertGreaterThanOrEqual(len, sampleRate * vad.minSpeechMs / 1000)
        }
        // First cut should land at exactly max samples.
        XCTAssertEqual(utterances[0].endSample - utterances[0].startSample, maxSamples)
    }

    /// Quiet-but-audible speech (RMS ~0.005) after a quiet room floor must segment.
    /// Absolute 0.012 would miss this — the Mac mic stall case.
    func testQuietConversationalSpeechSegments() {
        let vad = makeVAD()
        let frameSamples = sampleRate * vad.frameMs / 1000
        // 2s room floor + 4s quiet speech + 2s silence end.
        let floorFrames = 2_000 / vad.frameMs
        let speechFrames = 4_000 / vad.frameMs
        let trailFrames = 2_000 / vad.frameMs
        let totalFrames = floorFrames + speechFrames + trailFrames

        // Noise ~0.0008 RMS (amp ~26); speech ~0.005 RMS (amp ~164).
        let pcm = synthesizePCM(
            frameCount: totalFrames,
            frameSamples: frameSamples,
            amp: 0,
            voiced: { _ in false }
        )
        var mutable = pcm
        mutable.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for f in 0..<totalFrames {
                let base = f * frameSamples
                let amp: Int16
                if f < floorFrames {
                    amp = 26
                } else if f < floorFrames + speechFrames {
                    amp = 164
                } else {
                    amp = 20
                }
                for i in 0..<frameSamples {
                    samples[base + i] = amp
                }
            }
        }

        let probe = vad.probeEnergy(pcm: mutable, sampleRate: sampleRate)
        XCTAssertLessThan(probe.effectiveThreshold, 0.012, "must not stick to legacy 0.012 absolute")
        XCTAssertGreaterThan(probe.voicedFraction, 0.2, "quiet speech should mark frames voiced")

        let utterances = vad.segment(pcm: mutable, streamStartMs: 1_000, sampleRate: sampleRate)
        XCTAssertFalse(utterances.isEmpty, "quiet conversational speech above room floor must emit")
        let utt = utterances[0]
        XCTAssertGreaterThanOrEqual(utt.endSample - utt.startSample, sampleRate * vad.minSpeechMs / 1000)
    }

    /// Pure digital silence must not emit.
    func testSilenceDoesNotEmit() {
        let vad = makeVAD()
        let frameSamples = sampleRate * vad.frameMs / 1000
        let totalFrames = 10_000 / vad.frameMs // 10s zeros
        let pcm = Data(count: totalFrames * frameSamples * 2)
        let utterances = vad.segment(pcm: pcm, streamStartMs: 0, sampleRate: sampleRate)
        XCTAssertTrue(utterances.isEmpty)
        let probe = vad.probeEnergy(pcm: pcm, sampleRate: sampleRate)
        XCTAssertEqual(probe.voicedFraction, 0, accuracy: 0.001)
        XCTAssertEqual(probe.rmsPeak, 0, accuracy: 0.0001)
    }

    /// Flat continuous quiet speech (no silence reference) still segments via absolute floor.
    func testFlatQuietSpeechUsesAbsoluteFallback() {
        let vad = makeVAD()
        let frameSamples = sampleRate * vad.frameMs / 1000
        let totalFrames = 5_000 / vad.frameMs // 5s continuous quiet speech, no floor contrast
        let pcm = synthesizePCM(
            frameCount: totalFrames,
            frameSamples: frameSamples,
            amp: 180, // ~0.0055
            voiced: { _ in true }
        )
        let trail = synthesizePCM(
            frameCount: 2_000 / vad.frameMs,
            frameSamples: frameSamples,
            amp: 0,
            voiced: { _ in false }
        )
        var combined = pcm
        combined.append(trail)

        let utterances = vad.segment(pcm: combined, streamStartMs: 0, sampleRate: sampleRate)
        XCTAssertFalse(utterances.isEmpty, "flat quiet speech must use absolute energyThreshold fallback")
    }

    // MARK: - Helpers

    private func makeVAD() -> VoiceActivityDetector {
        let vad = VoiceActivityDetector()
        vad.minSpeechMs = 3_000
        vad.maxSpeechMs = 30_000
        vad.silenceEndMs = 1_750
        vad.frameMs = 30
        return vad
    }

    private func synthesizePCM(
        frameCount: Int,
        frameSamples: Int,
        amp: Int16,
        voiced: (Int) -> Bool
    ) -> Data {
        var pcm = Data(count: frameCount * frameSamples * 2)
        pcm.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for f in 0..<frameCount {
                guard voiced(f) else { continue }
                let base = f * frameSamples
                for i in 0..<frameSamples {
                    samples[base + i] = amp
                }
            }
        }
        return pcm
    }
}
