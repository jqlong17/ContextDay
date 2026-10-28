import XCTest
@testable import ContextDay

/// §2.9 four first-wave tools against a temp SQLite; unavailable tools stay unavailable.
final class AgentIOServiceTests: XCTestCase {
    private var tempDir: URL!
    private var store: SegmentStore!
    private var service: AgentIOService!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayAgentIO-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try SegmentStore.openIsolated(
            databaseURL: tempDir.appendingPathComponent("contextday.sqlite")
        )
        service = AgentIOService(store: store)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let seeds: [(String, SegmentTrack, Int64, String)] = [
            ("早上开会定了方案", .mic, now - 3_600_000, "speech"),
            ("下午听了播客", .system, now - 1_800_000, "music"),
            ("晚上复盘", .mic, now - 600_000, "speech"),
        ]
        for (text, track, t0, gate) in seeds {
            let seg = Segment(
                id: UUID(),
                track: track,
                t0Ms: t0,
                t1Ms: t0 + 5_000,
                tzAtCapture: "Asia/Shanghai",
                text: text,
                gateLabel: GateLabel(rawValue: gate),
                audioPath: nil,
                sourceSegmentIds: [],
                createdAtMs: t0,
                mergedAtMs: nil,
                mergeGapMs: nil,
                asrModelId: nil,
                asrModelVersion: nil
            )
            _ = try store.insertSegment(seg, mergeGapMs: 0)
        }
    }

    override func tearDownWithError() throws {
        service = nil
        store = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testEmptyStoreReturnsEmptyArrays() throws {
        let empty = try SegmentStore.openIsolated(
            databaseURL: tempDir.appendingPathComponent("empty.sqlite")
        )
        let emptyService = AgentIOService(store: empty)
        XCTAssertTrue(emptyService.searchSegments().isEmpty)
        XCTAssertTrue(emptyService.getRecent(limit: 10).isEmpty)
        XCTAssertTrue(try emptyService.getWindow(t0Ms: 0, t1Ms: 1).isEmpty)
        XCTAssertTrue(emptyService.listActivity().isEmpty)
    }

    func testSearchSegmentsByQueryAndTrack() {
        let hits = service.searchSegments(query: "开会", track: .mic)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.text, "早上开会定了方案")
        XCTAssertEqual(hits.first?.track, "mic")
    }

    func testGetRecentLimit() {
        let recent = service.getRecent(limit: 2)
        XCTAssertEqual(recent.count, 2)
        // Newest first
        XCTAssertEqual(recent.first?.text, "晚上复盘")
    }

    func testGetWindowOverlap() throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let window = try service.getWindow(t0Ms: now - 2_000_000, t1Ms: now)
        XCTAssertEqual(window.count, 2)
        XCTAssertThrowsError(try service.getWindow(t0Ms: 10, t1Ms: 5))
    }

    func testListActivityBuckets() {
        let buckets = service.listActivity()
        XCTAssertFalse(buckets.isEmpty)
        let total = buckets.reduce(0) { $0 + $1.segmentCount }
        XCTAssertEqual(total, 3)
    }

    func testProtocolDispatchFourTools() throws {
        for tool in AgentIOProtocol.firstWaveTools {
            let data = try AgentIOProtocol.dispatch(
                tool: tool,
                arguments: tool == "get_window"
                    ? ["t0_ms": 0, "t1_ms": Int64(Date().timeIntervalSince1970 * 1000) + 1]
                    : ["limit": 10],
                service: service
            )
            XCTAssertFalse(data.isEmpty, tool)
        }
    }

    func testUnavailableTools() {
        for tool in AgentIOProtocol.unavailableTools {
            XCTAssertThrowsError(
                try AgentIOProtocol.dispatch(tool: tool, arguments: [:], service: service)
            ) { error in
                guard let io = error as? AgentIOError, case .unavailable = io else {
                    return XCTFail("expected unavailable for \(tool)")
                }
            }
        }
    }
}
