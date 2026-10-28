import XCTest
@testable import ContextDay

final class RetentionDiskTests: XCTestCase {
    func testDeleteSegmentsOlderThanCutoff() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayRetention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SegmentStore.openIsolated(databaseURL: dir.appendingPathComponent("t.sqlite"))
        let old = Segment(
            id: UUID(), track: .mic, t0Ms: 1_000, t1Ms: 4_000,
            tzAtCapture: nil, text: "旧", gateLabel: .speech, audioPath: nil,
            sourceSegmentIds: [], createdAtMs: 1_000,
            mergedAtMs: nil, mergeGapMs: nil, asrModelId: nil, asrModelVersion: nil
        )
        let recent = Segment(
            id: UUID(), track: .mic, t0Ms: 9_000_000_000_000, t1Ms: 9_000_000_005_000,
            tzAtCapture: nil, text: "新", gateLabel: .speech, audioPath: nil,
            sourceSegmentIds: [], createdAtMs: 9_000_000_000_000,
            mergedAtMs: nil, mergeGapMs: nil, asrModelId: nil, asrModelVersion: nil
        )
        _ = try store.insertSegment(old, mergeGapMs: 0)
        _ = try store.insertSegment(recent, mergeGapMs: 0)
        let removed = try store.deleteSegments(t1BeforeMs: 5_000)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.queryRecent(limit: 10, track: nil).count, 1)
        XCTAssertEqual(store.queryRecent(limit: 10, track: nil).first?.text, "新")
    }

    func testDiskSpaceGuardReturnsStatus() {
        let status = DiskSpaceGuard.status()
        XCTAssertGreaterThan(status.freeBytes, 0)
        // On a healthy CI/dev volume we should not block keep-audio.
        // Do not assert !blockKeepAudio — sandboxes / tiny disks may legitimately block.
        _ = status.blockKeepAudio
    }
}
