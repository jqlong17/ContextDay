import XCTest
@testable import ContextDay

/// Offline-friendly diagnostics: permissions encode, runtime desync, self_check shape.
final class DiagnosticsSelfCheckTests: XCTestCase {
    func testPermissionSnapshotEncodes() throws {
        let snap = PermissionStatus.snapshot()
        XCTAssertEqual(snap.entries.count, 4)
        XCTAssertNotNil(snap.entry(.microphone))
        XCTAssertEqual(snap.entry(.accessibility)?.state, .notApplicable)
        XCTAssertEqual(snap.entry(.automation)?.state, .notApplicable)
        let data = try JSONEncoder().encode(snap)
        XCTAssertFalse(data.isEmpty)
    }

    func testRuntimeHealthDesyncFlag() {
        let health = RuntimeHealth.shared
        health.setUIWantsRecording(true)
        health.setPipelineRunning(false)
        XCTAssertTrue(health.recordingDesync)
        health.setPipelineRunning(true)
        XCTAssertFalse(health.recordingDesync)
        health.setUIWantsRecording(false)
        health.setPipelineRunning(false)
        health.clearCaptureError()
    }

    func testSelfCheckReportAgainstTempDB() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDaySelfCheck-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("contextday.sqlite")
        let store = try SegmentStore.openIsolated(databaseURL: dbURL)
        let health = RuntimeHealth.shared
        health.setUIWantsRecording(false)
        health.setPipelineRunning(false)

        let report = SelfCheck.run(
            store: store,
            health: health,
            agentListening: true,
            agentPort: 18787
        )
        XCTAssertEqual(report.service, "ContextDay")
        XCTAssertTrue(report.database.openable)
        XCTAssertFalse(report.runtime.recordingDesync)
        XCTAssertEqual(report.agentIO.port, 18787)

        let data = try AgentIOProtocol.encodeJSON(report)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["service"] as? String, "ContextDay")
        XCTAssertNotNil(obj?["permissions"])
        XCTAssertNotNil(obj?["models"])
    }

    func testClipboardIndexIsShortAndPointsAtSkills() {
        let text = AgentPromptTemplate.makeClipboardIndex(
            recordsRoot: URL(fileURLWithPath: "/tmp/ContextDayRecordsTest")
        )
        XCTAssertLessThan(text.count, 600, "clipboard must stay a short index")
        XCTAssertTrue(text.contains("助手索引"))
        XCTAssertTrue(text.contains("get_agent_skill") || text.contains("get_recent"))
        XCTAssertFalse(text.contains("Segment 字段摘要"))
        XCTAssertFalse(text.contains("docs/agent-skills"))
        XCTAssertFalse(text.contains("Spec §"))
    }

    func testFullPromptLongerThanClipboardIndex() {
        let root = URL(fileURLWithPath: "/tmp/ContextDayRecordsTest")
        let index = AgentPromptTemplate.makeClipboardIndex(recordsRoot: root)
        let full = AgentPromptTemplate.makeFullPrompt(recordsRoot: root)
        XCTAssertGreaterThan(full.count, index.count)
        XCTAssertTrue(full.contains("Segment 字段摘要"))
        XCTAssertTrue(full.contains("get_clipboard_prompt 仅返回短"))
    }

    func testSelfCheckToolDispatch() throws {
        let data = try AgentIOProtocol.dispatch(tool: "self_check", arguments: [:])
        let report = try JSONDecoder().decode(SelfCheck.Report.self, from: data)
        XCTAssertEqual(report.service, "ContextDay")
    }
}
