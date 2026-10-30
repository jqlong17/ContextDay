import AppKit
import XCTest
@testable import ContextDay

final class OnboardingFlowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        OnboardingStore.resetCompletedFlag()
    }

    override func tearDown() {
        OnboardingStore.resetCompletedFlag()
        super.tearDown()
    }

    func testShouldPresentWhileOnboardingIncomplete() {
        // v0.3.21: gateReady no longer suppresses the bubble — first-run owns permission CTA.
        XCTAssertTrue(OnboardingFlow.shouldPresent(completed: false, gateReady: false))
        XCTAssertFalse(OnboardingFlow.shouldPresent(completed: true, gateReady: false))
        XCTAssertTrue(OnboardingFlow.shouldPresent(completed: false, gateReady: true))
        XCTAssertFalse(OnboardingFlow.shouldPresent(completed: true, gateReady: true))
    }

    func testIntroIsChunkedNotSingleBlob() {
        XCTAssertGreaterThanOrEqual(OnboardingFlow.introCount, 3)
        XCTAssertLessThanOrEqual(OnboardingFlow.introCount, 5)
        for (i, seg) in OnboardingFlow.introSegments.enumerated() {
            XCTAssertFalse(seg.isEmpty, "segment \(i) empty")
            // Each chunk stays digestible; full dump would be much longer in one piece.
            XCTAssertLessThan(seg.count, 160, "segment \(i) too long for one bubble step")
        }
        let joined = OnboardingFlow.introSegments.joined()
        XCTAssertTrue(joined.contains("ContextDay") || joined.contains("主人"))
        XCTAssertTrue(joined.contains("本地") || joined.contains("本机"))
    }

    func testPermissionChecklistHasCoreItems() {
        let ids = Set(OnboardingFlow.permissionItems.map(\.id))
        XCTAssertEqual(OnboardingFlow.permissionItems.count, 4)
        XCTAssertTrue(ids.contains("login_item"))
        XCTAssertTrue(ids.contains("microphone"))
        XCTAssertTrue(ids.contains("screen_recording"))
        XCTAssertTrue(ids.contains("records_folder"))
    }

    func testLoginItemIsInformationalOnly() {
        let login = OnboardingFlow.permissionItems.first { $0.id == "login_item" }
        XCTAssertEqual(login?.requirement, .informational)
        XCTAssertTrue(OnboardingFlow.informationalItems.contains { $0.id == "login_item" })
        XCTAssertFalse(OnboardingFlow.recordingRequiredItems.contains { $0.id == "login_item" })
        let requiredIDs = Set(OnboardingFlow.recordingRequiredItems.map(\.id))
        XCTAssertEqual(requiredIDs, ["microphone", "screen_recording", "records_folder"])
    }

    func testCanStartCaptureIgnoresLoginItem() {
        // Only Login Item missing → still can start.
        let loginOnlyMissing = OnboardingFlow.PermissionFlags(
            loginItemOK: false,
            microphoneOK: true,
            screenRecordingOK: true,
            recordsFolderOK: true
        )
        XCTAssertTrue(OnboardingFlow.canStartCapture(flags: loginOnlyMissing))
        XCTAssertTrue(OnboardingFlow.missingRecordingRequired(flags: loginOnlyMissing).isEmpty)

        // Mic missing → cannot start, even if Login Item OK.
        let micMissing = OnboardingFlow.PermissionFlags(
            loginItemOK: true,
            microphoneOK: false,
            screenRecordingOK: true,
            recordsFolderOK: true
        )
        XCTAssertFalse(OnboardingFlow.canStartCapture(flags: micMissing))
        XCTAssertEqual(
            OnboardingFlow.missingRecordingRequired(flags: micMissing).map(\.id),
            ["microphone"]
        )

        // Screen + folder missing.
        let multi = OnboardingFlow.PermissionFlags(
            loginItemOK: false,
            microphoneOK: true,
            screenRecordingOK: false,
            recordsFolderOK: false
        )
        XCTAssertFalse(OnboardingFlow.canStartCapture(flags: multi))
        XCTAssertEqual(
            Set(OnboardingFlow.missingRecordingRequired(flags: multi).map(\.id)),
            ["screen_recording", "records_folder"]
        )
    }

    func testConversationalCopyForDeferMissingAndReady() {
        XCTAssertTrue(OnboardingFlow.deferredSkipMessage.contains("暂时还不能完成录制"))
        XCTAssertTrue(OnboardingFlow.deferredSkipMessage.contains("再检查权限"))

        let one = OnboardingFlow.missingRequiredMessage(missingTitles: ["麦克风"])
        XCTAssertTrue(one.contains("麦克风"))
        XCTAssertTrue(one.contains("尚未开通"))
        XCTAssertTrue(one.contains("不能完成录制"))

        let two = OnboardingFlow.missingRequiredMessage(
            missingTitles: ["麦克风", "屏幕录制（系统声）"]
        )
        XCTAssertTrue(two.contains("麦克风和屏幕录制（系统声）"))

        let three = OnboardingFlow.missingRequiredMessage(
            missingTitles: ["麦克风", "屏幕录制（系统声）", "记录文件夹可写"]
        )
        XCTAssertTrue(three.contains("麦克风、屏幕录制（系统声）和记录文件夹可写"))

        XCTAssertEqual(OnboardingFlow.readyToWorkMessage, "那开始工作")
        XCTAssertEqual(OnboardingFlow.returnToBackgroundMessage, "我先回到后台")
        XCTAssertFalse(OnboardingFlow.permissionsIntroBody.isEmpty)
    }

    func testOnboardingStoreMarkCompleted() {
        XCTAssertFalse(OnboardingStore.isCompleted)
        OnboardingStore.markCompleted()
        XCTAssertTrue(OnboardingStore.isCompleted)
        OnboardingStore.resetCompletedFlag()
        XCTAssertFalse(OnboardingStore.isCompleted)
    }

    func testIntroSegmentBounds() {
        XCTAssertNotNil(OnboardingFlow.introSegment(at: 0))
        XCTAssertNil(OnboardingFlow.introSegment(at: -1))
        XCTAssertNil(OnboardingFlow.introSegment(at: OnboardingFlow.introCount))
    }

    func testMayAutoSyncSystemPreferencesOnlyAfterOnboardingCompleted() {
        // v0.3.21: launch never auto-syncs Login Item / TCC while onboarding incomplete,
        // even when the ready gate is already green (bubble still owns the CTA).
        XCTAssertFalse(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: false, gateReady: false)
        )
        XCTAssertFalse(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: false, gateReady: true)
        )
        // After onboarding finished (grant or skip) → launch may sync Login Item preference.
        XCTAssertTrue(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: true, gateReady: false)
        )
        XCTAssertTrue(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: true, gateReady: true)
        )
        // maySync == completed; shouldPresent == !completed (gateReady ignored for both).
        for completed in [false, true] {
            for gateReady in [false, true] {
                let present = OnboardingFlow.shouldPresent(completed: completed, gateReady: gateReady)
                let maySync = OnboardingFlow.mayAutoSyncSystemPreferences(
                    completed: completed, gateReady: gateReady
                )
                XCTAssertEqual(present, !completed, "present completed=\(completed) gateReady=\(gateReady)")
                XCTAssertEqual(maySync, completed, "maySync completed=\(completed) gateReady=\(gateReady)")
                XCTAssertEqual(maySync, !present, "inverse completed=\(completed) gateReady=\(gateReady)")
            }
        }
    }

    func testBubbleLayoutConceptACompactConstants() {
        // Concept A: tighter card than the original ~312×196 light chrome.
        XCTAssertLessThanOrEqual(OnboardingBubbleLayout.bubbleWidth, 300)
        XCTAssertLessThanOrEqual(OnboardingBubbleLayout.bubbleHeightIntro, 170)
        XCTAssertLessThan(OnboardingBubbleLayout.bubbleHeightIntro, OnboardingBubbleLayout.bubbleHeightPerms)
        XCTAssertLessThanOrEqual(OnboardingBubbleLayout.contentPadding, 14)
        XCTAssertGreaterThanOrEqual(OnboardingBubbleLayout.cornerRadius, 12)
        XCTAssertGreaterThanOrEqual(OnboardingBubbleLayout.tailHeight, 8)
        XCTAssertEqual(OnboardingBubbleLayout.pillHeight, 28, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(OnboardingBubbleLayout.prevButtonWidth, 64)
        XCTAssertGreaterThan(OnboardingBubbleLayout.gapAboveOrb, 0)
        // Soft green is clearly green-dominant (not gray / pink).
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        OnboardingBubbleLayout.softGreen.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(g, r)
        XCTAssertGreaterThan(g, b)
        XCTAssertGreaterThan(a, 0.9)
    }

    func testIntroSupportsSteppingBackAfterFirstPage() {
        // v0.3.26: multi-page intro must be reversible after page 0.
        XCTAssertGreaterThanOrEqual(OnboardingFlow.introCount, 3)
        for i in 1..<OnboardingFlow.introCount {
            XCTAssertNotNil(OnboardingFlow.introSegment(at: i - 1), "prev target for page \(i)")
        }
    }
}
