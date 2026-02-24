import Foundation
import SwiftData

@Model
public final class LocalUser {
    @Attribute(.unique) public var id: String
    public var providerRawValue: String
    public var providerUserId: String?
    public var email: String?
    public var displayName: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        providerRawValue: String,
        providerUserId: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.providerRawValue = providerRawValue
        self.providerUserId = providerUserId
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
