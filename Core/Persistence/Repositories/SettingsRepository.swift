import Foundation
import SwiftData

@MainActor
public final class SettingsRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func settings() throws -> AppLocalSettings {
        var descriptor = FetchDescriptor<AppLocalSettings>()
        let existingSettings = try context.fetch(descriptor)

        if let primary = existingSettings.first {
            var requiresSave = false

            if primary.id != AppLocalSettings.singletonId {
                primary.id = AppLocalSettings.singletonId
                requiresSave = true
            }

            for duplicate in existingSettings.dropFirst() {
                context.delete(duplicate)
                requiresSave = true
            }

            if requiresSave {
                try context.save()
            }

            return primary
        }

        let created = AppLocalSettings()
        context.insert(created)
        try context.save()
        return created
    }

    public func setCurrentUser(id: String, provider: AuthProvider) throws {
        let currentSettings = try settings()
        currentSettings.currentUserId = id
        currentSettings.lastSignedInProviderRaw = provider.rawValue
        try context.save()
    }

    public func clearCurrentUser() throws {
        let currentSettings = try settings()
        currentSettings.currentUserId = nil
        try context.save()
    }

    public func notificationPromptState() throws -> NotificationPromptState {
        let currentSettings = try settings()
        guard let rawValue = currentSettings.notificationPromptStateRaw else {
            return .neverAsked
        }
        return NotificationPromptState(rawValue: rawValue) ?? .neverAsked
    }

    public func setNotificationPromptState(_ state: NotificationPromptState, promptedAt: Date? = nil) throws {
        let currentSettings = try settings()
        currentSettings.notificationPromptStateRaw = state.rawValue
        if let promptedAt {
            currentSettings.notificationPromptedAt = promptedAt
        }
        try context.save()
    }

    public func notificationAuthorizationStatus() throws -> NotificationAuthorizationStatus {
        let currentSettings = try settings()
        guard let rawValue = currentSettings.notificationAuthorizationStatusRaw else {
            return .notDetermined
        }
        return NotificationAuthorizationStatus(rawValue: rawValue) ?? .notDetermined
    }

    public func setNotificationAuthorizationStatus(_ status: NotificationAuthorizationStatus) throws {
        let currentSettings = try settings()
        currentSettings.notificationAuthorizationStatusRaw = status.rawValue
        try context.save()
    }

    public func lastActiveAt() throws -> Date? {
        try settings().lastActiveAt
    }

    public func setLastActiveAt(_ date: Date) throws {
        let currentSettings = try settings()
        currentSettings.lastActiveAt = date
        try context.save()
    }
}
