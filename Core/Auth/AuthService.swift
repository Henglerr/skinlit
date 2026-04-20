import AuthenticationServices
import Foundation

@MainActor
public protocol AuthService {
    var isGoogleSignInAvailable: Bool { get }
    var hasStoredBackendSession: Bool { get }
    var lastGuestBackendSessionErrorDescription: String? { get }

    func restoreSession() async -> AuthSession?
    func continueAsGuestForBootstrap() async throws -> AuthSession
    func signInWithApple(result: Result<ASAuthorization, Error>) async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func continueAsGuest() async throws -> AuthSession
    func signOut() async throws
    func deleteAccount() async throws
}
