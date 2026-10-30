import XCTest
@testable import ContextDay

/// Spec T07 / T08 / T20 / v0.3.23 near-dup + out-of-order overlap fold.
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

    /// Near-identical windows (Mac 2026-10-30 symptom): fold to one row, keep longer text, no concat.
    func testNearDuplicateWindowFoldsWithoutConcatenatingText() throws {
        let a = makeSegment(
            id: UUID(), track: .mic,
            t0: 1_000, t1: 4_690, text: "那个耳机不是然后我定了"
        )
        let b = makeSegment(
            id: UUID(), track: .mic,
            t0: 1_002, t1: 4_692, text: "那个耳机不是那是这个着急的这个不知道然后我定了"
        )
        let first = try store.insertSegment(a, mergeGapMs: 2_000)
        let folded = try store.insertSegment(b, mergeGapMs: 2_000)

        XCTAssertEqual(folded.id, first.id)
        XCTAssertEqual(store.queryRecent(limit: 10, track: .mic).count, 1)
        XCTAssertEqual(folded.text, b.text, "near-dup keeps longer ASR text")
        XCTAssertFalse(folded.text?.contains("那个耳机不是然后我定了那个耳机") == true)
        XCTAssertNotNil(folded.mergedAtMs)
        XCTAssertEqual(folded.sourceSegmentIds.count, 2)
    }

    /// Late re-insert of an earlier window after a newer segment exists must still fold
    /// (latest-by-t0 alone missed this — root cause of 3.8× inflation).
    func testLateNearDuplicateFoldsDespiteNewerLatestRow() throws {
        let early = makeSegment(
            id: UUID(), track: .mic,
            t0: 10_000, t1: 13_690, text: "早段短"
        )
        let later = makeSegment(
            id: UUID(), track: .mic,
            t0: 20_000, t1: 23_000, text: "较新一段"
        )
        let earlyDup = makeSegment(
            id: UUID(), track: .mic,
            t0: 10_005, t1: 13_695, text: "早段短但ASR稍长一点"
        )
        _ = try store.insertSegment(early, mergeGapMs: 2_000)
        _ = try store.insertSegment(later, mergeGapMs: 2_000)
        let folded = try store.insertSegment(earlyDup, mergeGapMs: 2_000)

        let rows = store.queryRecent(limit: 10, track: .mic)
        XCTAssertEqual(rows.count, 2, "early cluster folds; later stays separate")
        XCTAssertEqual(folded.id, early.id)
        XCTAssertEqual(folded.text, earlyDup.text)
        let laterRow = rows.first { $0.id == later.id }
        XCTAssertEqual(laterRow?.text, "较新一段")
    }

    func testOverlapMergesAdjacentNonDuplicateWithOrderedConcat() throws {
        let a = makeSegment(id: UUID(), track: .mic, t0: 1_000, t1: 4_000, text: "前")
        let b = makeSegment(id: UUID(), track: .mic, t0: 3_500, t1: 7_000, text: "后")
        // Overlap 500ms, not near-dup (overlap/minDur = 500/3000 < 80%)
        let merged = try store.insertSegment(a, mergeGapMs: 2_000)
        let out = try store.insertSegment(b, mergeGapMs: 2_000)
        XCTAssertEqual(out.id, merged.id)
        XCTAssertEqual(out.text, "前后")
        XCTAssertEqual(out.t0Ms, 1_000)
        XCTAssertEqual(out.t1Ms, 7_000)
    }

    func testSeparationMsAndNearDupHelpers() {
        let a = makeSegment(id: UUID(), track: .mic, t0: 1_000, t1: 4_000, text: "a")
        let b = makeSegment(id: UUID(), track: .mic, t0: 5_000, t1: 8_000, text: "b")
        let c = makeSegment(id: UUID(), track: .mic, t0: 1_050, t1: 4_050, text: "c")
        XCTAssertEqual(SegmentMerger.separationMs(previous: a, incoming: b), 1_000)
        XCTAssertEqual(SegmentMerger.separationMs(previous: a, incoming: c), 0)
        XCTAssertTrue(SegmentMerger.isNearDuplicateWindow(previous: a, incoming: c))
        XCTAssertFalse(SegmentMerger.isNearDuplicateWindow(previous: a, incoming: b))
        XCTAssertTrue(
            SegmentMerger.isNearDuplicateInterval(a0: 100, a1: 4000, b0: 120, b1: 4010)
        )
    }

    func testMergedTextCapPreventsRunaway() {
        let long = String(repeating: "字", count: SegmentMerger.maxMergedTextChars + 50)
        let capped = SegmentMerger.cappedText(long)
        XCTAssertEqual(capped?.count, SegmentMerger.maxMergedTextChars)
    }

    /// v0.3.23 emission bug: overlap/min(dur) blocked longer refinements after a short emit.
    /// Capture must use `isAlreadyEmittedInterval` so extensions still reach ASR.
    func testEmissionDedupeAllowsExtensionButBlocksJitterAndContained() {
        // Same-window jitter (±tens of ms) → skip
        XCTAssertTrue(
            SegmentMerger.isAlreadyEmittedInterval(a0: 1_000, a1: 4_690, b0: 1_002, b1: 4_692)
        )
        // Longer refinement of short prior emit → MUST send (store near-dup folds later)
        XCTAssertFalse(
            SegmentMerger.isAlreadyEmittedInterval(a0: 1_000, a1: 5_000, b0: 1_000, b1: 20_000),
            "extension must not be treated as already-emitted"
        )
        // Old store helper still calls this a near-dup (fold text, don't concat) — fine for DB
        XCTAssertTrue(
            SegmentMerger.isNearDuplicateInterval(a0: 1_000, a1: 5_000, b0: 1_000, b1: 20_000),
            "document: store fold still sees extension as near-dup via minDur ratio"
        )
        // Short window fully inside an already-emitted long one → skip re-ASR
        XCTAssertTrue(
            SegmentMerger.isAlreadyEmittedInterval(a0: 0, a1: 30_000, b0: 10_000, b1: 13_000)
        )
        // Adjacent new speech → send
        XCTAssertFalse(
            SegmentMerger.isAlreadyEmittedInterval(a0: 0, a1: 30_000, b0: 31_000, b1: 35_000)
        )
        // Empty emitted list semantics: nothing to compare — caller skips the contains check
        // Spam window from Mac 2026-10-30 → skip
        XCTAssertTrue(
            SegmentMerger.isAlreadyEmittedInterval(
                a0: 1_793_355_032_850, a1: 1_793_355_036_550,
                b0: 1_793_355_032_887, b1: 1_793_355_036_577
            )
        )
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
