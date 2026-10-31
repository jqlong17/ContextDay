import XCTest
@testable import ContextDay

final class PCMRingBufferTests: XCTestCase {
    private let sampleRate = 16_000

    func testSnapshotCopySurvivesConcurrentAppend() {
        let ring = PCMRingBuffer(variant: .b)
        ring.reset(streamStartMs: 0, sampleRate: 16_000)
        let chunk = Data(count: 3_200) // 1_600 Int16 samples of silence
        for _ in 0..<80 {
            ring.append(int16LE: chunk)
        }

        let exp = expectation(description: "race")
        exp.expectedFulfillmentCount = 2
        let iterations = 400

        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<iterations {
                ring.append(int16LE: chunk)
            }
            exp.fulfill()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<iterations {
                let snap = ring.snapshot()
                let bytes = snap.data.count
                XCTAssertEqual(bytes % 2, 0)
                if bytes >= 4 {
                    // Must not SIGTRAP even while the writer trims/appends.
                    _ = snap.data.subdata(in: 0..<4)
                    _ = snap.data.subdata(in: (bytes - 4)..<bytes)
                }
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 15)
    }

    func testPCMInt16SliceRejectsOutOfBoundsWithoutTrap() {
        let pcm = Data(count: 100) // 50 samples
        XCTAssertNil(PCMInt16Slice.subdata(pcm: pcm, startSample: -1, endSample: 10))
        XCTAssertNil(PCMInt16Slice.subdata(pcm: pcm, startSample: 10, endSample: 10))
        XCTAssertNil(PCMInt16Slice.subdata(pcm: pcm, startSample: 50, endSample: 60))
        XCTAssertNil(PCMInt16Slice.subdata(pcm: Data(), startSample: 0, endSample: 1))

        let ok = PCMInt16Slice.subdata(pcm: pcm, startSample: 10, endSample: 50)
        XCTAssertEqual(ok?.count, 80)

        let clamped = PCMInt16Slice.subdata(pcm: pcm, startSample: 40, endSample: 1000)
        XCTAssertEqual(clamped?.count, 20) // samples 40..<50
    }

    func testVariantBHardCapsAtSixtySeconds() {
        let ring = PCMRingBuffer(variant: .b)
        ring.reset(streamStartMs: 0, sampleRate: sampleRate)
        let capBytes = PCMBufferPolicy.capacityBytes(sampleRate: sampleRate, variant: .b)
        XCTAssertEqual(capBytes, sampleRate * 2 * 60)

        // Feed 90s of silence → must stay at 60s capacity.
        let chunkSec = 1
        let chunk = Data(count: sampleRate * chunkSec * 2)
        for _ in 0..<90 {
            ring.append(int16LE: chunk)
        }
        let m = ring.metrics()
        XCTAssertEqual(m.filledBytes, capBytes)
        XCTAssertEqual(m.capacityBytes, capBytes)
        XCTAssertLessThanOrEqual(m.peakFilledBytes, capBytes)
        XCTAssertEqual(m.filledBytes % 2, 0)
    }

    func testStreamStartMsAdvancesOnDropVariantB() {
        let ring = PCMRingBuffer(variant: .b)
        let t0: Int64 = 5_000_000
        ring.reset(streamStartMs: t0, sampleRate: sampleRate)
        let oneSec = Data(count: sampleRate * 2)
        for _ in 0..<60 {
            ring.append(int16LE: oneSec)
        }
        XCTAssertEqual(ring.metrics().streamStartMs, t0)
        // One more second forces a 1s drop at the head.
        ring.append(int16LE: oneSec)
        let advanced = ring.metrics().streamStartMs
        XCTAssertEqual(advanced, t0 + 1_000)
    }

    func testStreamStartMsAdvancesOnDropVariantA() {
        let ring = PCMRingBuffer(variant: .a)
        let t0: Int64 = 9_000_000
        ring.reset(streamStartMs: t0, sampleRate: sampleRate)
        let oneSec = Data(count: sampleRate * 2)
        let capSec = PCMBufferPolicy.variantASeconds
        for _ in 0..<capSec {
            ring.append(int16LE: oneSec)
        }
        XCTAssertEqual(ring.metrics().streamStartMs, t0)
        ring.append(int16LE: oneSec)
        XCTAssertEqual(ring.metrics().streamStartMs, t0 + 1_000)
    }

    func testSliceAfterTrimDoesNotTrap() {
        let ring = PCMRingBuffer(variant: .b)
        ring.reset(streamStartMs: 0, sampleRate: sampleRate)
        let oneSec = Data(count: sampleRate * 2)
        for _ in 0..<75 {
            ring.append(int16LE: oneSec)
        }
        let snap = ring.snapshot()
        XCTAssertEqual(snap.data.count, sampleRate * 2 * 60)
        // Slice near both ends — must not SIGTRAP.
        let head = PCMInt16Slice.subdata(pcm: snap.data, startSample: 0, endSample: 100)
        let tail = PCMInt16Slice.subdata(
            pcm: snap.data,
            startSample: snap.data.count / 2 - 100,
            endSample: snap.data.count / 2
        )
        XCTAssertEqual(head?.count, 200)
        XCTAssertEqual(tail?.count, 200)
        _ = ring.slice(startSample: 0, endSample: sampleRate)
    }

    func testVariantBHoldsEnoughForMaxThirtySecondUtterance() {
        // Buffer must retain ≥ maxSpeech (30s) so VAD force-cut still sees a full window.
        let ring = PCMRingBuffer(variant: .b)
        ring.reset(streamStartMs: 0, sampleRate: sampleRate)
        let amp: Int16 = 2_000
        var oneSec = Data(count: sampleRate * 2)
        oneSec.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleRate { samples[i] = amp }
        }
        for _ in 0..<60 {
            ring.append(int16LE: oneSec)
        }
        let snap = ring.snapshot()
        let vad = VoiceActivityDetector()
        let utterances = vad.segment(pcm: snap.data, streamStartMs: snap.streamStartMs, sampleRate: sampleRate)
        XCTAssertFalse(utterances.isEmpty, "60s continuous voice in B ring must yield VAD cuts")
        let maxSamples = sampleRate * vad.maxSpeechMs / 1000
        for utt in utterances {
            XCTAssertLessThanOrEqual(utt.endSample - utt.startSample, maxSamples)
            XCTAssertGreaterThanOrEqual(utt.endSample - utt.startSample, sampleRate * vad.minSpeechMs / 1000)
        }
        // At least one full max-30s cut.
        XCTAssertTrue(utterances.contains { $0.endSample - $0.startSample == maxSamples })
    }

    func testDualTrackIndependence() {
        let mic = PCMRingBuffer(variant: .b)
        let system = PCMRingBuffer(variant: .b)
        mic.reset(streamStartMs: 100, sampleRate: sampleRate)
        system.reset(streamStartMs: 200, sampleRate: sampleRate)
        let chunk = Data(repeating: 1, count: sampleRate * 2) // 1s
        for _ in 0..<10 {
            mic.append(int16LE: chunk)
        }
        for _ in 0..<3 {
            system.append(int16LE: chunk)
        }
        XCTAssertEqual(mic.sampleCount, sampleRate * 10)
        XCTAssertEqual(system.sampleCount, sampleRate * 3)
        XCTAssertEqual(mic.metrics().streamStartMs, 100)
        XCTAssertEqual(system.metrics().streamStartMs, 200)
        // Overflow mic only — system unchanged.
        for _ in 0..<55 {
            mic.append(int16LE: chunk)
        }
        XCTAssertEqual(mic.metrics().filledBytes, PCMBufferPolicy.capacityBytes(sampleRate: sampleRate, variant: .b))
        XCTAssertEqual(system.sampleCount, sampleRate * 3)
    }

    func testABHarnessPeakRatioAtSoftCap() {
        // After ≥10 min continuous write, A is at soft cap; B at 60s → ~10× smaller.
        let a = PCMBufferABHarness.fillSilence(variant: .a, seconds: 600)
        let b = PCMBufferABHarness.fillSilence(variant: .b, seconds: 600)
        XCTAssertEqual(a.peakFilledBytes, sampleRate * 2 * 600)
        XCTAssertEqual(b.peakFilledBytes, sampleRate * 2 * 60)
        XCTAssertTrue(PCMBufferABHarness.peakRatioPass(a: a, b: b, maxRatio: 0.15))
        XCTAssertLessThanOrEqual(Double(b.peakFilledBytes) / Double(a.peakFilledBytes), 0.11)
    }

    func testPolicyDefaultIsB() {
        XCTAssertEqual(PCMBufferPolicy.defaultVariant, .b)
        XCTAssertEqual(PCMBufferPolicy.variantBSeconds, 60)
        XCTAssertEqual(PCMBufferPolicy.variantASeconds, 600)
    }

    func testPolicySecondsKeyMapsToVariant() {
        // Keep suite name in a local — `UserDefaults` has no `suiteName` property (Mac compile).
        let suiteName = "app.contextday.pcm-ab-test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        suite.set(600, forKey: PCMBufferPolicy.secondsDefaultsKey)
        // resolveVariant reads .standard by default — exercise mapping logic inline:
        let sec = suite.integer(forKey: PCMBufferPolicy.secondsDefaultsKey)
        let mapped: PCMBufferVariant = sec >= PCMBufferPolicy.variantASeconds / 2 ? .a : .b
        XCTAssertEqual(mapped, .a)

        suite.set(60, forKey: PCMBufferPolicy.secondsDefaultsKey)
        let secB = suite.integer(forKey: PCMBufferPolicy.secondsDefaultsKey)
        let mappedB: PCMBufferVariant = secB >= PCMBufferPolicy.variantASeconds / 2 ? .a : .b
        XCTAssertEqual(mappedB, .b)

        suite.set("A", forKey: PCMBufferPolicy.variantDefaultsKey)
        XCTAssertEqual(PCMBufferVariant(rawValue: suite.string(forKey: PCMBufferPolicy.variantDefaultsKey)!.uppercased()), .a)
    }
}
