import Foundation
import UserNotifications

public enum ReengagementStage: String, Codable, CaseIterable {
    case onboardingIncomplete
    case noScansYet
    case hasScanHistory
}

public enum NotificationPromptState: String, Codable, CaseIterable {
    case neverAsked
    case softDeclined
    case systemDenied
    case authorized
}

public enum NotificationAuthorizationStatus: String, Codable, CaseIterable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .denied
        }
    }

    public var isAuthorized: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        }
    }
}

public enum NotificationOpenIntent: String, Codable {
    case resumeOnboarding
    case openFirstScan
    case openHome
}

public struct ReengagementContext: Equatable {
    public let userId: String
    public let goal: String?
    public let hasCompletedOnboarding: Bool
    public let hasAnyScan: Bool
    public let lastActiveAt: Date
    public let resumeRoute: AppRoute?
    public let latestScanDate: Date?

    public init(
        userId: String,
        goal: String?,
        hasCompletedOnboarding: Bool,
        hasAnyScan: Bool,
        lastActiveAt: Date,
        resumeRoute: AppRoute?,
        latestScanDate: Date?
    ) {
        self.userId = userId
        self.goal = goal
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasAnyScan = hasAnyScan
        self.lastActiveAt = lastActiveAt
        self.resumeRoute = resumeRoute
        self.latestScanDate = latestScanDate
    }
}

public struct PlannedReengagementNotification: Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let interval: TimeInterval
    public let stage: ReengagementStage
    public let openIntent: NotificationOpenIntent

    public init(
        id: String,
        title: String,
        body: String,
        interval: TimeInterval,
        stage: ReengagementStage,
        openIntent: NotificationOpenIntent
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.interval = interval
        self.stage = stage
        self.openIntent = openIntent
    }
}

public protocol UserNotificationCenterProtocol: AnyObject {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol {
    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await notificationSettings()
        return NotificationAuthorizationStatus(settings.authorizationStatus)
    }
}
