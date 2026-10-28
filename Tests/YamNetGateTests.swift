import XCTest
@testable import ContextDay

/// Music > Speech bias (Spec §1.4) + optional ONNX classify when models are present.
final class YamNetGateTests: XCTestCase {
    func testDecideLabelMusicPreferredWhenBothHigh() {
        XCTAssertEqual(
            YamNetGate.decideLabel(speechScore: 0.8, musicScore: 0.8),
            .music
        )
        XCTAssertEqual(
            YamNetGate.decideLabel(speechScore: 0.9, musicScore: 0.91),
            .music
        )
    }

    func testDecideLabelSpeechWhenMusicLow() {
        XCTAssertEqual(
            YamNetGate.decideLabel(speechScore: 0.7, musicScore: 0.05),
            .speech
        )
    }

    func testDecideLabelOtherWhenBelowThreshold() {
        XCTAssertEqual(
            YamNetGate.decideLabel(speechScore: 0.05, musicScore: 0.05),
            .other
        )
    }

    func testDecideLabelMusicAlone() {
        XCTAssertEqual(
            YamNetGate.decideLabel(speechScore: 0.02, musicScore: 0.6),
            .music
        )
    }

    /// When Bundle Models/YAMNet is present, classify a short fixture waveform (does not assert label).
    func testClassifyFixtureWaveformIfModelPresent() throws {
        guard ModelBundlePaths.yamnetONNX.map({ FileManager.default.fileExists(atPath: $0.path) }) == true,
              ModelBundlePaths.yamnetClassMap.map({ FileManager.default.fileExists(atPath: $0.path) }) == true
        else {
            throw XCTSkip("YAMNet models missing under Resources/Models/YAMNet — run Scripts/fetch-models.sh")
        }

        let gate = YamNetGate()
        try gate.loadModelIfNeeded()
        XCTAssertTrue(gate.isModelLoaded)

        // ~1s of 440 Hz tone @ 16 kHz Int16 LE (fixture waveform).
        let pcm = Self.sineWavePCM(hz: 440, seconds: 1.0, sampleRate: 16_000)
        let result = gate.classify(
            track: .mic,
            pcmWindow: pcm,
            windowStartMs: 0,
            windowEndMs: 1_000
        )
        XCTAssertTrue([GateLabel.speech, .music, .other].contains(result.label))
        // Bias invariant still holds on raw scores from the run.
        let decided = YamNetGate.decideLabel(
            speechScore: result.speechScore,
            musicScore: result.musicScore
        )
        XCTAssertEqual(decided, result.label)
    }

    private static func sineWavePCM(hz: Double, seconds: Double, sampleRate: Int) -> Data {
        let n = Int(Double(sampleRate) * seconds)
        var data = Data(count: n * 2)
        data.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            for i in 0..<n {
                let t = Double(i) / Double(sampleRate)
                let sample = sin(2 * Double.pi * hz * t) * 0.4
                buf[i] = Int16(max(-1, min(1, sample)) * Double(Int16.max))
            }
        }
        return data
    }
}
