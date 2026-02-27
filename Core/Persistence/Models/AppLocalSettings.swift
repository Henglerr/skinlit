import Foundation
import SwiftData

@Model
public final class AppLocalSettings {
    @Attribute(.unique) public var id: String
    public var currentUserId: String?
    public var lastSignedInProviderRaw: String?
    public var notificationPromptStateRaw: String?
    public var notificationPromptedAt: Date?
    public var notificationAuthorizationStatusRaw: String?
    public var lastActiveAt: Date?

    public init(
        id: String = AppLocalSettings.singletonId,
        currentUserId: String? = nil,
        lastSignedInProviderRaw: String? = nil,
        notificationPromptStateRaw: String? = nil,
        notificationPromptedAt: Date? = nil,
        notificationAuthorizationStatusRaw: String? = nil,
        lastActiveAt: Date? = nil
    ) {
        self.id = id
        self.currentUserId = currentUserId
        self.lastSignedInProviderRaw = lastSignedInProviderRaw
        self.notificationPromptStateRaw = notificationPromptStateRaw
        self.notificationPromptedAt = notificationPromptedAt
        self.notificationAuthorizationStatusRaw = notificationAuthorizationStatusRaw
        self.lastActiveAt = lastActiveAt
    }

    public static let singletonId = "app-local-settings"
}
