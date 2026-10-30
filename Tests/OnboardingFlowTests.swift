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

    func testShouldPresentOnlyWhenIncompleteAndNotReady() {
        XCTAssertTrue(OnboardingFlow.shouldPresent(completed: false, gateReady: false))
        XCTAssertFalse(OnboardingFlow.shouldPresent(completed: true, gateReady: false))
        XCTAssertFalse(OnboardingFlow.shouldPresent(completed: false, gateReady: true))
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

    func testMayAutoSyncSystemPreferencesDefersWhileOnboardingOwnsCTA() {
        // First-run bubble path: incomplete + gate not ready → no auto Login Item / TCC on launch.
        XCTAssertFalse(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: false, gateReady: false)
        )
        // After onboarding finished (grant or skip) → launch may sync Login Item preference.
        XCTAssertTrue(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: true, gateReady: false)
        )
        // Gate already green (permissions ready) even if flag unset → bubble skipped; sync OK.
        XCTAssertTrue(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: false, gateReady: true)
        )
        XCTAssertTrue(
            OnboardingFlow.mayAutoSyncSystemPreferences(completed: true, gateReady: true)
        )
        // Inverse of shouldPresent.
        for completed in [false, true] {
            for gateReady in [false, true] {
                let present = OnboardingFlow.shouldPresent(completed: completed, gateReady: gateReady)
                let maySync = OnboardingFlow.mayAutoSyncSystemPreferences(
                    completed: completed, gateReady: gateReady
                )
                XCTAssertEqual(maySync, !present, "completed=\(completed) gateReady=\(gateReady)")
            }
        }
    }
}
