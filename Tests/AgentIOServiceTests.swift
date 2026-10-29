import XCTest
@testable import ContextDay

/// §2.9 / 02 tools against a temp SQLite; unavailable tools stay unavailable.
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
        XCTAssertTrue(try emptyService.listSpeechBlocks().isEmpty)
    }

    func testSearchSegmentsByQueryAndTrack() {
        let hits = service.searchSegments(query: "开会", track: .mic)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.text, "早上开会定了方案")
        XCTAssertEqual(hits.first?.track, "mic")
        XCTAssertFalse(hits.first?.t0Iso.isEmpty ?? true)
        XCTAssertTrue(hits.first?.t0Iso.contains("+08:00") == true || hits.first?.t0Iso.hasSuffix("Z") == true)
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

    func testListActivityPerTrackDensity() {
        let buckets = service.listActivity()
        XCTAssertFalse(buckets.isEmpty)
        let mic = buckets.filter { $0.track == "mic" }
        let system = buckets.filter { $0.track == "system" }
        let totals = buckets.filter { $0.track == nil }
        XCTAssertFalse(mic.isEmpty)
        XCTAssertFalse(system.isEmpty)
        XCTAssertFalse(totals.isEmpty)
        let micSegs = mic.reduce(0) { $0 + $1.segmentCount }
        let sysSegs = system.reduce(0) { $0 + $1.segmentCount }
        let totalSegs = totals.reduce(0) { $0 + $1.segmentCount }
        XCTAssertEqual(micSegs + sysSegs, totalSegs)
        XCTAssertEqual(micSegs + sysSegs, 3)
        XCTAssertTrue(mic.contains { $0.speechCount >= 1 })
        XCTAssertFalse(buckets.first?.bucketStartIso.isEmpty ?? true)
    }

    func testListActivityWithoutTotal() {
        let buckets = service.listActivity(includeTotal: false)
        XCTAssertTrue(buckets.allSatisfy { $0.track != nil })
    }

    func testListSpeechBlocksMergesWithinGap() throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let blocks = try service.listSpeechBlocks(
            t0Ms: now - 4 * 3_600_000,
            t1Ms: now + 1,
            track: .mic,
            gapMs: 3_600_000
        )
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].segmentCount, 2)
        XCTAssertEqual(blocks[0].track, "mic")
        XCTAssertEqual(blocks[0].gapMsUsed, 3_600_000)
        XCTAssertFalse(blocks[0].t0Iso.isEmpty)
    }

    func testListSpeechBlocksRejectsNonPositiveGap() {
        XCTAssertThrowsError(try service.listSpeechBlocks(gapMs: 0)) { error in
            guard let io = error as? AgentIOError, case .invalidArgument = io else {
                return XCTFail("expected invalid_argument")
            }
        }
    }

    func testIso8601ShanghaiStable() {
        // 2024-10-29 08:02:00.000+08:00 (fixture meetingT0 + 120s)
        let ms: Int64 = 1_730_160_120_000
        let iso = AgentIOTime.iso8601(epochMs: ms, timeZoneIdentifier: "Asia/Shanghai")
        XCTAssertTrue(iso.hasPrefix("2024-10-29T08:02:00"), iso)
        XCTAssertTrue(iso.contains("+08:00"), iso)
    }

    func testProtocolDispatchTools() throws {
        for tool in AgentIOProtocol.firstWaveTools {
            let args: [String: Any]
            switch tool {
            case "get_window":
                args = ["t0_ms": 0, "t1_ms": Int64(Date().timeIntervalSince1970 * 1000) + 1]
            case "list_speech_blocks":
                args = ["limit": 10, "gap_ms": 120_000]
            default:
                args = ["limit": 10]
            }
            let data = try AgentIOProtocol.dispatch(tool: tool, arguments: args, service: service)
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
                XCTAssertEqual(io.payload["error"], "unavailable")
                XCTAssertEqual(io.payload["tool"], tool)
                XCTAssertFalse(io.payload["message"]?.isEmpty ?? true)
                XCTAssertEqual(io.httpStatus, 501)
            }
        }
    }

    func testUnifiedNotFoundPayload() {
        let err = AgentIOError.notFound("no such route")
        XCTAssertEqual(err.payload["error"], "not_found")
        XCTAssertEqual(err.payload["message"], "no such route")
        XCTAssertEqual(err.httpStatus, 404)
    }
}
