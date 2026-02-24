import Foundation
import SwiftData

@MainActor
public final class UserRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func user(byId id: String) throws -> LocalUser? {
        let predicate = #Predicate<LocalUser> { $0.id == id }
        var descriptor = FetchDescriptor<LocalUser>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func user(provider: AuthProvider, providerUserId: String?) throws -> LocalUser? {
        let providerRaw = provider.rawValue
        let providerId = providerUserId ?? ""
        let predicate = #Predicate<LocalUser> {
            $0.providerRawValue == providerRaw && ($0.providerUserId ?? "") == providerId
        }
        var descriptor = FetchDescriptor<LocalUser>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func createGuestUser() throws -> LocalUser {
        let user = LocalUser(
            providerRawValue: AuthProvider.guest.rawValue,
            providerUserId: nil,
            email: nil,
            displayName: "Guest"
        )
        context.insert(user)
        try context.save()
        return user
    }

    public func findOrCreateUser(
        provider: AuthProvider,
        providerUserId: String?,
        email: String?,
        displayName: String?
    ) throws -> LocalUser {
        if let providerUserId, let existing = try user(provider: provider, providerUserId: providerUserId) {
            existing.email = email ?? existing.email
            existing.displayName = displayName ?? existing.displayName
            existing.updatedAt = .now
            try context.save()
            return existing
        }

        let user = LocalUser(
            providerRawValue: provider.rawValue,
            providerUserId: providerUserId,
            email: email,
            displayName: displayName
        )
        context.insert(user)
        try context.save()
        return user
    }
}
