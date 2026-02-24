import Foundation
import SwiftData

@Model
public final class AppLocalSettings {
    @Attribute(.unique) public var id: String
    public var currentUserId: String?
    public var lastSignedInProviderRaw: String?

    public init(
        id: String = AppLocalSettings.singletonId,
        currentUserId: String? = nil,
        lastSignedInProviderRaw: String? = nil
    ) {
        self.id = id
        self.currentUserId = currentUserId
        self.lastSignedInProviderRaw = lastSignedInProviderRaw
    }

    public static let singletonId = "app-local-settings"
}
