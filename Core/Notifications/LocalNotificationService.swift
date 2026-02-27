import Foundation
import UserNotifications

public protocol NotificationService: AnyObject {
    func refreshAuthorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async -> NotificationPromptState
    func rescheduleReengagementNotifications(context: ReengagementContext) async
    func cancelReengagementNotifications() async
    func consumePendingOpenIntent() -> NotificationOpenIntent?
}

public final class LocalNotificationService: NSObject, NotificationService, UNUserNotificationCenterDelegate {
    private enum UserInfoKey {
        static let intent = "notificationOpenIntent"
        static let stage = "reengagementStage"
        static let userId = "userId"
    }

    private let center: UserNotificationCenterProtocol
    private let planner: ReengagementPlanner
    private let stateQueue = DispatchQueue(label: "com.skinscore.notifications.state")
    private var pendingOpenIntent: NotificationOpenIntent?

    public init(
        center: UserNotificationCenterProtocol,
        planner: ReengagementPlanner = ReengagementPlanner()
    ) {
        self.center = center
        self.planner = planner
    }

    public func refreshAuthorizationStatus() async -> NotificationAuthorizationStatus {
        await center.authorizationStatus()
    }

    public func requestAuthorization() async -> NotificationPromptState {
        do {
            let isGranted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return isGranted ? .authorized : .systemDenied
        } catch {
            return .systemDenied
        }
    }

    public func rescheduleReengagementNotifications(context: ReengagementContext) async {
        await clearExistingReengagementRequests()

        let authorizationStatus = await refreshAuthorizationStatus()
        guard authorizationStatus.isAuthorized else { return }

        let notifications = planner.notifications(for: context)
        guard !notifications.isEmpty else { return }

        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.threadIdentifier = ReengagementPlanner.notificationThreadIdentifier
            content.userInfo = [
                UserInfoKey.intent: notification.openIntent.rawValue,
                UserInfoKey.stage: notification.stage.rawValue,
                UserInfoKey.userId: context.userId
            ]

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(notification.interval, 1),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: trigger
            )

            try? await center.add(request)
        }
    }

    public func cancelReengagementNotifications() async {
        await clearExistingReengagementRequests()
    }

    public func consumePendingOpenIntent() -> NotificationOpenIntent? {
        stateQueue.sync {
            defer { pendingOpenIntent = nil }
            return pendingOpenIntent
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let rawIntent = response.notification.request.content.userInfo[UserInfoKey.intent] as? String,
              let intent = NotificationOpenIntent(rawValue: rawIntent) else {
            return
        }

        stateQueue.sync {
            pendingOpenIntent = intent
        }
    }

    private func clearExistingReengagementRequests() async {
        let pendingRequests = await center.pendingNotificationRequests()
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(ReengagementPlanner.identifierPrefix) }

        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
