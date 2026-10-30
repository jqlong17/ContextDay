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
}
