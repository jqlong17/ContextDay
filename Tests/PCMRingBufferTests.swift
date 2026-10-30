import XCTest
@testable import ContextDay

final class PCMRingBufferTests: XCTestCase {
    func testSnapshotCopySurvivesConcurrentAppend() {
        let ring = PCMRingBuffer()
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
}
