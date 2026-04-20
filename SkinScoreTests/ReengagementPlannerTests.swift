import XCTest
@testable import SkinLit

final class ReengagementPlannerTests: XCTestCase {
    func testOnboardingIncompleteProducesExpectedNotifications() {
        let planner = ReengagementPlanner(cadence: [86_400, 259_200, 604_800])
        let context = ReengagementContext(
            userId: "user-1",
            goal: "Glow",
            hasCompletedOnboarding: false,
            hasAnyScan: false,
            lastActiveAt: .now,
            resumeRoute: .onboardingRoutine,
            latestScanDate: nil
        )

        let notifications = planner.notifications(for: context)

        XCTAssertEqual(planner.stage(for: context), .onboardingIncomplete)
        XCTAssertEqual(notifications.count, 3)
        XCTAssertEqual(notifications.map(\.id), [
            "reengagement.day1",
            "reengagement.day3",
            "reengagement.day7"
        ])
        XCTAssertEqual(notifications.map(\.title), [
            "Finish your setup",
            "Your profile is waiting",
            "Pick up where you left off"
        ])
        XCTAssertEqual(notifications.map(\.openIntent), [.resumeOnboarding, .resumeOnboarding, .resumeOnboarding])
    }

    func testNoScansYetProducesExpectedNotifications() {
        let planner = ReengagementPlanner(cadence: [86_400, 259_200, 604_800])
        let context = ReengagementContext(
            userId: "user-2",
            goal: "Hydration",
            hasCompletedOnboarding: true,
            hasAnyScan: false,
            lastActiveAt: .now,
            resumeRoute: nil,
            latestScanDate: nil
        )

        let notifications = planner.notifications(for: context)

        XCTAssertEqual(planner.stage(for: context), .noScansYet)
        XCTAssertEqual(notifications.count, 3)
        XCTAssertEqual(notifications[0].body, "Your profile is ready. Open SkinLit to see your baseline.")
        XCTAssertEqual(notifications[1].body, "Start tracking your skin with a quick first scan.")
        XCTAssertEqual(notifications[2].body, "One scan is enough to begin your skin progress history.")
        XCTAssertEqual(notifications.map(\.openIntent), [.openFirstScan, .openFirstScan, .openFirstScan])
    }

    func testHasScanHistoryProducesExpectedNotifications() {
        let planner = ReengagementPlanner(cadence: [86_400, 259_200, 604_800])
        let context = ReengagementContext(
            userId: "user-3",
            goal: "Even Tone",
            hasCompletedOnboarding: true,
            hasAnyScan: true,
            lastActiveAt: .now,
            resumeRoute: nil,
            latestScanDate: .now.addingTimeInterval(-86_400)
        )

        let notifications = planner.notifications(for: context)

        XCTAssertEqual(planner.stage(for: context), .hasScanHistory)
        XCTAssertEqual(notifications.count, 3)
        XCTAssertEqual(notifications.map(\.title), [
            "Time for a fresh scan",
            "Track your progress",
            "Consistency beats guesswork"
        ])
        XCTAssertEqual(notifications.map(\.openIntent), [.openHome, .openHome, .openHome])
    }
}
