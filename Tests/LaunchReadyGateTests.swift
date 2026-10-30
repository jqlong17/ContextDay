import XCTest
@testable import ContextDay

final class LaunchReadyGateTests: XCTestCase {
    func testReadyWhenAllGatesPass() {
        let perms = PermissionSnapshot(
            checkedAtMs: 0,
            entries: [
                PermissionEntry(kind: .microphone, state: .authorized, reason: "test"),
                PermissionEntry(kind: .screenRecording, state: .authorized, reason: "test"),
                PermissionEntry(kind: .accessibility, state: .notApplicable, reason: "n/a"),
                PermissionEntry(kind: .automation, state: .notApplicable, reason: "n/a"),
            ]
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayReady-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = LaunchReadyGate.evaluate(permissions: perms, recordsRoot: dir)
        XCTAssertTrue(result.isReady)
        XCTAssertTrue(result.micAuthorized)
        XCTAssertTrue(result.screenAuthorized)
        XCTAssertTrue(result.recordsWritable)
    }

    func testNotReadyWhenMicDenied() {
        let perms = PermissionSnapshot(
            checkedAtMs: 0,
            entries: [
                PermissionEntry(kind: .microphone, state: .denied, reason: "test"),
                PermissionEntry(kind: .screenRecording, state: .authorized, reason: "test"),
                PermissionEntry(kind: .accessibility, state: .notApplicable, reason: "n/a"),
                PermissionEntry(kind: .automation, state: .notApplicable, reason: "n/a"),
            ]
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextDayReady-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertFalse(LaunchReadyGate.isReady(permissions: perms, recordsRoot: dir))
    }

    func testAppConfigOpenAtLoginDefaultOn() {
        XCTAssertTrue(AppConfig.default.openAtLogin)
    }
}
