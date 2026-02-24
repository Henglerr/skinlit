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
    public let isSignedIn: Bool

    public init(
        localUserId: String,
        provider: AuthProvider,
        providerUserId: String?,
        email: String?,
        displayName: String?,
        isSignedIn: Bool = true
    ) {
        self.localUserId = localUserId
        self.provider = provider
        self.providerUserId = providerUserId
        self.email = email
        self.displayName = displayName
        self.isSignedIn = isSignedIn
    }
}

public enum AuthError: LocalizedError {
    case cancelled
    case invalidAppleCredential
    case googleNotConfigured
    case presentationContextMissing
    case sessionPersistenceFailed
    case signInFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidAppleCredential:
            return "Could not read Apple sign-in credentials."
        case .googleNotConfigured:
            return "Google sign-in is not configured yet."
        case .presentationContextMissing:
            return "Could not present the sign-in flow."
        case .sessionPersistenceFailed:
            return "Could not save your local session."
        case .signInFailed(let message):
            return message
        }
    }
}
