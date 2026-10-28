import XCTest
@testable import ContextDay

/// Spec T07 / T08 / T20 — merge gap ≤2s, no-merge >2s, earliest audio_path kept.
final class SegmentStoreMergeTests: XCTestCase {
    private var tempDir: URL!
    private var store: SegmentStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayMergeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("contextday.sqlite")
        store = try SegmentStore.openIsolated(databaseURL: dbURL)
    }

    override func tearDownWithError() throws {
        store = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testMergeWhenGapWithinTwoSeconds() throws {
        let a = makeSegment(
            id: UUID(), track: .mic,
            t0: 1_000, t1: 4_000, text: "你好",
            audio: "audio/2026-10-28/mic/a.opus"
        )
        let b = makeSegment(
            id: UUID(), track: .mic,
            t0: 5_500, t1: 8_000, text: "世界",
            audio: "audio/2026-10-28/mic/b.opus"
        )
        // gap = 1500ms ≤ 2000
        let first = try store.insertSegment(a, mergeGapMs: 2_000)
        let merged = try store.insertSegment(b, mergeGapMs: 2_000)

        XCTAssertEqual(merged.id, first.id)
        XCTAssertEqual(merged.t0Ms, 1_000)
        XCTAssertEqual(merged.t1Ms, 8_000)
        XCTAssertEqual(merged.text, "你好世界")
        XCTAssertEqual(merged.audioPath, "audio/2026-10-28/mic/a.opus")
        XCTAssertNotNil(merged.mergedAtMs)
        XCTAssertEqual(merged.mergeGapMs, 2_000)

        let rows = store.queryRecent(limit: 10, track: .mic)
        XCTAssertEqual(rows.count, 1)
    }

    func testNoMergeWhenGapExceedsTwoSeconds() throws {
        let a = makeSegment(id: UUID(), track: .mic, t0: 1_000, t1: 4_000, text: "甲")
        let b = makeSegment(id: UUID(), track: .mic, t0: 7_001, t1: 10_000, text: "乙")
        // gap = 3001ms > 2000
        _ = try store.insertSegment(a, mergeGapMs: 2_000)
        _ = try store.insertSegment(b, mergeGapMs: 2_000)

        let rows = store.queryRecent(limit: 10, track: .mic)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.text)), Set(["甲", "乙"]))
    }

    func testDifferentTracksDoNotMerge() throws {
        let mic = makeSegment(id: UUID(), track: .mic, t0: 1_000, t1: 4_000, text: "麦")
        let sys = makeSegment(id: UUID(), track: .system, t0: 4_100, t1: 7_000, text: "系统")
        _ = try store.insertSegment(mic, mergeGapMs: 2_000)
        _ = try store.insertSegment(sys, mergeGapMs: 2_000)
        XCTAssertEqual(store.queryRecent(limit: 10, track: nil).count, 2)
    }

    func testConcatenateTextHasNoExtraWhitespace() {
        XCTAssertEqual(SegmentMerger.concatenateText("你好", "世界"), "你好世界")
        XCTAssertEqual(SegmentMerger.concatenateText(nil, "只右"), "只右")
        XCTAssertNil(SegmentMerger.concatenateText("  ", nil))
    }

    private func makeSegment(
        id: UUID,
        track: SegmentTrack,
        t0: Int64,
        t1: Int64,
        text: String?,
        audio: String? = nil
    ) -> Segment {
        Segment(
            id: id,
            track: track,
            t0Ms: t0,
            t1Ms: t1,
            tzAtCapture: "Asia/Shanghai",
            text: text,
            gateLabel: .speech,
            audioPath: audio,
            sourceSegmentIds: [],
            createdAtMs: t0,
            mergedAtMs: nil,
            mergeGapMs: nil,
            asrModelId: "test",
            asrModelVersion: "1"
        )
    }
}
