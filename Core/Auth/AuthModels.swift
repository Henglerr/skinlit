import Foundation

public enum AuthProvider: String, Codable, CaseIterable {
    case guest
    case apple
    case google
}

public struct AuthSession: Codable, Equatable {
    public let localUserId: String
    public let provider: AuthProvider
    public let providerUserId: String?
    public let email: String?
    public let displayName: String?
    public let remoteUserId: String?
    public let isSignedIn: Bool

    public init(
        localUserId: String,
        provider: AuthProvider,
        providerUserId: String?,
        email: String?,
        displayName: String?,
        remoteUserId: String? = nil,
        isSignedIn: Bool = true
    ) {
        self.localUserId = localUserId
        self.provider = provider
        self.providerUserId = providerUserId
        self.email = email
        self.displayName = displayName
        self.remoteUserId = remoteUserId
        self.isSignedIn = isSignedIn
    }

    public var usesRemoteBackend: Bool {
        remoteUserId?.isEmpty == false
    }
}

public enum AuthError: LocalizedError {
    case cancelled
    case invalidAppleCredential
    case missingProviderToken
    case googleNotConfigured
    case guestModeUnavailable
    case backendNotConfigured
    case presentationContextMissing
    case sessionPersistenceFailed
    case noActiveSession
    case accountDeletionFailed
    case signInFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidAppleCredential:
            return "Could not read Apple sign-in credentials."
        case .missingProviderToken:
            return "Could not obtain a valid identity token from the sign-in provider."
        case .googleNotConfigured:
            return "Google sign-in is not configured yet."
        case .guestModeUnavailable:
            return "Guest access is unavailable right now."
        case .backendNotConfigured:
            return "Cloud analysis is not configured for this build."
        case .presentationContextMissing:
            return "Could not present the sign-in flow."
        case .sessionPersistenceFailed:
            return "Could not save your local session."
        case .noActiveSession:
            return "No active session was found."
        case .accountDeletionFailed:
            return "Could not delete your local account data."
        case .signInFailed(let message):
            return message
        }
    }
}
