import UserNotifications
import XCTest
@testable import SkinScore

final class LocalNotificationServiceTests: XCTestCase {
    func testRescheduleRemovesExistingRequestsBeforeAddingNewOnes() async {
        let center = MockUserNotificationCenter()
        center.authorizationStatusValue = .authorized
        center.pendingRequests = [
            makeRequest(identifier: "reengagement.day1"),
            makeRequest(identifier: "other.notification")
        ]

        let service = LocalNotificationService(
            center: center,
            planner: ReengagementPlanner(cadence: [60, 180, 420])
        )
        let context = ReengagementContext(
            userId: "user-1",
            goal: "Glow",
            hasCompletedOnboarding: true,
            hasAnyScan: false,
            lastActiveAt: .now,
            resumeRoute: nil,
            latestScanDate: nil
        )

        await service.rescheduleReengagementNotifications(context: context)

        XCTAssertEqual(center.removedIdentifiers, ["reengagement.day1"])
        XCTAssertEqual(center.addedRequests.map(\.identifier), [
            "reengagement.day1",
            "reengagement.day3",
            "reengagement.day7"
        ])
    }

    func testRescheduleDoesNotAddRequestsWhenAuthorizationIsNotGranted() async {
        let center = MockUserNotificationCenter()
        center.authorizationStatusValue = .denied
        center.pendingRequests = [
            makeRequest(identifier: "reengagement.day1"),
            makeRequest(identifier: "reengagement.day3")
        ]

        let service = LocalNotificationService(
            center: center,
            planner: ReengagementPlanner(cadence: [60, 180, 420])
        )
        let context = ReengagementContext(
            userId: "user-2",
            goal: "Hydration",
            hasCompletedOnboarding: true,
            hasAnyScan: true,
            lastActiveAt: .now,
            resumeRoute: nil,
            latestScanDate: .now
        )

        await service.rescheduleReengagementNotifications(context: context)

        XCTAssertEqual(center.removedIdentifiers.sorted(), ["reengagement.day1", "reengagement.day3"])
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    private func makeRequest(identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: nil
        )
    }
}

private final class MockUserNotificationCenter: UserNotificationCenterProtocol {
    var authorizationStatusValue: NotificationAuthorizationStatus = .notDetermined
    var requestAuthorizationResult = false
    var pendingRequests: [UNNotificationRequest] = []
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
        pendingRequests.append(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingRequests
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        pendingRequests.removeAll { identifiers.contains($0.identifier) }
    }
}
