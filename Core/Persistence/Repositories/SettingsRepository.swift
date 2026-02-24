import Foundation
import SwiftData

@MainActor
public final class SettingsRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func settings() throws -> AppLocalSettings {
        let singletonId = AppLocalSettings.singletonId
        let predicate = #Predicate<AppLocalSettings> { $0.id == singletonId }
        var descriptor = FetchDescriptor<AppLocalSettings>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
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
}
