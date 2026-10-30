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
