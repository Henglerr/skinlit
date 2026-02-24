import AuthenticationServices
import Foundation

@MainActor
public protocol AuthService {
    var isGoogleSignInAvailable: Bool { get }

    func restoreSession() async -> AuthSession?
    func signInWithApple(result: Result<ASAuthorization, Error>) async throws -> AuthSession
    func signInWithGoogle() async throws -> AuthSession
    func continueAsGuest() async throws -> AuthSession
    func signOut() async throws
}
