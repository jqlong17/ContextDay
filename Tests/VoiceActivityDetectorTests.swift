import XCTest
@testable import ContextDay

final class VoiceActivityDetectorTests: XCTestCase {
    /// Silence spanning the max boundary, then voice again, must still cap ≤ max samples.
    func testTrailingSilenceDoesNotExceedMaxSpeechSamples() {
        let vad = VoiceActivityDetector()
        vad.minSpeechMs = 3_000
        vad.maxSpeechMs = 30_000
        vad.silenceEndMs = 1_750
        vad.frameMs = 30
        vad.energyThreshold = 0.012

        let sampleRate = 16_000
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
}
