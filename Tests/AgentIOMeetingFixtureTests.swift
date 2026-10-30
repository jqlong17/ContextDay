import XCTest
@testable import ContextDay

/// Meeting-minutes style fixture: insert speech segments (as if ASR’d from sample audio)
/// → round-trip search / recent / window / activity / speech_blocks with stable JSON keys.
/// Full dual-rail capture cannot run headless on Linux CI; this is the offline stand-in.
final class AgentIOMeetingFixtureTests: XCTestCase {
    private var tempDir: URL!
    private var store: SegmentStore!
    private var service: AgentIOService!
    private var meetingT0: Int64 = 0
    private var meetingT1: Int64 = 0
    private var seedIds: [UUID] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayMeetingIO-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try SegmentStore.openIsolated(
            databaseURL: tempDir.appendingPathComponent("contextday.sqlite")
        )
        service = AgentIOService(store: store)

        // Simulated 25-minute standup (mic speech + one system music bed that must not block Q&A).
        meetingT0 = 1_730_160_000_000 // fixed epoch for stable fixtures
        let lines: [(String, SegmentTrack, Int64, GateLabel, String?)] = [
            ("大家好，今天站会开始。先同步一下发布进度。", .mic, 0, .speech, nil),
            ("我这边 API 已经合入 main，还差文档。", .mic, 45_000, .speech, "audio/2024-10-28/mic/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.wav"),
            ("决议：周五前完成上线检查清单。", .mic, 120_000, .speech, nil),
            ("待办：小王写 QA 步骤，小李盯回归。", .mic, 180_000, .speech, nil),
            ("背景音乐继续播放", .system, 90_000, .music, nil),
            ("风险：第三方回调偶发超时，先记未决。", .mic, 240_000, .speech, nil),
        ]
        seedIds = []
        for (text, track, offset, gate, audio) in lines {
            let id = UUID()
            seedIds.append(id)
            let t0 = meetingT0 + offset
            let seg = Segment(
                id: id,
                track: track,
                t0Ms: t0,
                t1Ms: t0 + 8_000,
                tzAtCapture: "Asia/Shanghai",
                text: text,
                gateLabel: gate,
                audioPath: audio,
                sourceSegmentIds: [],
                createdAtMs: t0,
                mergedAtMs: nil,
                mergeGapMs: nil,
                asrModelId: "sensevoice-coreml-int8",
                asrModelVersion: "fixture"
            )
            _ = try store.insertSegment(seg, mergeGapMs: 0)
        }
        meetingT1 = meetingT0 + 300_000
    }

    override func tearDownWithError() throws {
        service = nil
        store = nil
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testSearchByKeywordForMinutes() throws {
        let data = try AgentIOProtocol.dispatch(
            tool: "search_segments",
            arguments: ["query": "决议", "track": "mic", "t0_ms": meetingT0, "t1_ms": meetingT1],
            service: service
        )
        let rows = try JSONDecoder().decode([AgentSegmentDTO].self, from: data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].track, "mic")
        XCTAssertEqual(rows[0].gateLabel, "speech")
        XCTAssertTrue(rows[0].text?.contains("决议") == true)
        XCTAssertEqual(rows[0].tzAtCapture, "Asia/Shanghai")
        XCTAssertTrue(rows[0].t0Iso.contains("+08:00"))
        assertSnakeCaseKeys(data, required: ["segment_id", "t0_ms", "t1_ms", "t0_iso", "t1_iso", "track", "text"])
    }

    func testGetWindowIncludesOverlappingSpeechAndMusic() throws {
        let data = try AgentIOProtocol.dispatch(
            tool: "get_window",
            arguments: ["t0_ms": meetingT0, "t1_ms": meetingT1],
            service: service
        )
        let rows = try JSONDecoder().decode([AgentSegmentDTO].self, from: data)
        XCTAssertEqual(rows.count, 6)
        let micSpeech = rows.filter { $0.track == "mic" && $0.gateLabel == "speech" }
        let systemMusic = rows.filter { $0.track == "system" && $0.gateLabel == "music" }
        XCTAssertEqual(micSpeech.count, 5)
        XCTAssertEqual(systemMusic.count, 1)
        // Assistant can ignore music for minutes while still seeing mic speech.
        XCTAssertTrue(micSpeech.contains { $0.text?.contains("待办") == true })
    }

    func testGetRecentAndListActivityShapes() throws {
        // get_recent by limit — newest first
        let recentData = try AgentIOProtocol.dispatch(
            tool: "get_recent",
            arguments: ["limit": 3],
            service: service
        )
        let recent = try JSONDecoder().decode([AgentSegmentDTO].self, from: recentData)
        XCTAssertEqual(recent.count, 3)
        XCTAssertGreaterThanOrEqual(recent[0].t0Ms, recent[1].t0Ms)

        let activityData = try AgentIOProtocol.dispatch(
            tool: "list_activity",
            arguments: ["t0_ms": meetingT0, "t1_ms": meetingT1],
            service: service
        )
        let buckets = try JSONDecoder().decode([AgentActivityBucketDTO].self, from: activityData)
        XCTAssertFalse(buckets.isEmpty)
        let mic = buckets.filter { $0.track == "mic" }
        let system = buckets.filter { $0.track == "system" }
        let totals = buckets.filter { $0.track == nil }
        XCTAssertEqual(mic.reduce(0) { $0 + $1.segmentCount }, 5)
        XCTAssertEqual(system.reduce(0) { $0 + $1.segmentCount }, 1)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.segmentCount }, 6)
        assertSnakeCaseKeys(
            activityData,
            required: [
                "bucket_start_ms", "bucket_end_ms", "bucket_start_iso", "bucket_end_iso",
                "segment_count", "speech_count", "music_count", "other_count",
            ]
        )
    }

    func testListSpeechBlocksForLongMeetingPattern() throws {
        let data = try AgentIOProtocol.dispatch(
            tool: "list_speech_blocks",
            arguments: [
                "t0_ms": meetingT0,
                "t1_ms": meetingT1,
                "track": "mic",
                "gap_ms": 120_000,
            ],
            service: service
        )
        let blocks = try JSONDecoder().decode([AgentSpeechBlockDTO].self, from: data)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].segmentCount, 5)
        XCTAssertEqual(blocks[0].gapMsUsed, 120_000)
        XCTAssertEqual(blocks[0].segmentIds.count, 5)
        XCTAssertTrue(blocks[0].speechChars > 0)
        assertSnakeCaseKeys(
            data,
            required: [
                "track", "t0_ms", "t1_ms", "t0_iso", "t1_iso",
                "segment_count", "speech_chars", "segment_ids", "gap_ms_used",
            ]
        )

        // Split with tiny gap → multiple blocks
        let splitData = try AgentIOProtocol.dispatch(
            tool: "list_speech_blocks",
            arguments: [
                "t0_ms": meetingT0,
                "t1_ms": meetingT1,
                "track": "mic",
                "gap_ms": 10_000,
            ],
            service: service
        )
        let split = try JSONDecoder().decode([AgentSpeechBlockDTO].self, from: splitData)
        XCTAssertGreaterThan(split.count, 1)
    }

    func testMaxCharsTruncationStable() throws {
        let data = try AgentIOProtocol.dispatch(
            tool: "search_segments",
            arguments: ["query": "站会", "max_chars": 8],
            service: service
        )
        let rows = try JSONDecoder().decode([AgentSegmentDTO].self, from: data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].text?.count, 8)
    }

    func testAudioPathSurfacedWhenPresent() throws {
        let hits = service.searchSegments(query: "API", track: .mic)
        XCTAssertEqual(hits.count, 1)
        XCTAssertNotNil(hits[0].audioPath)
        XCTAssertTrue(hits[0].audioPath?.hasPrefix("audio/") == true)
    }

    func testUnavailableSummarizeHasClearPayload() throws {
        XCTAssertThrowsError(
            try AgentIOProtocol.dispatch(tool: "summarize_window", arguments: [:], service: service)
        ) { error in
            guard let io = error as? AgentIOError else { return XCTFail("type") }
            let payload = io.payload
            XCTAssertEqual(payload["error"], "unavailable")
            XCTAssertEqual(payload["tool"], "summarize_window")
            XCTAssertFalse(payload["message"]?.isEmpty ?? true)
        }
    }

    func testEncodedJSONIsLLMFriendlySortedKeys() throws {
        let data = try AgentIOProtocol.dispatch(
            tool: "get_window",
            arguments: ["t0_ms": meetingT0 + 40_000, "t1_ms": meetingT0 + 50_000],
            service: service
        )
        let text = String(data: data, encoding: .utf8) ?? ""
        // sortedKeys → audio_path before gate_label before segment_id …
        XCTAssertTrue(text.contains("\"audio_path\""))
        XCTAssertTrue(text.contains("\"segment_id\""))
        XCTAssertTrue(text.contains("\"tz_at_capture\""))
        XCTAssertTrue(text.contains("\"t0_iso\""))
        XCTAssertFalse(text.contains("segmentId")) // no camelCase leak
    }

    private func assertSnakeCaseKeys(_ data: Data, required: [String]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return XCTFail("not JSON")
        }
        let dicts: [[String: Any]]
        if let arr = json as? [[String: Any]] {
            dicts = arr
        } else if let one = json as? [String: Any] {
            dicts = [one]
        } else {
            return XCTFail("unexpected JSON root")
        }
        guard let first = dicts.first else { return XCTFail("empty") }
        for key in required {
            XCTAssertTrue(first.keys.contains(key), "missing \(key) in \(first.keys.sorted())")
        }
    }
}
