import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

@MainActor
public final class LocalAuthService: AuthService {
    private let userRepository: UserRepository
    private let onboardingRepository: OnboardingRepository
    private let analysisRepository: AnalysisRepository
    private let settingsRepository: SettingsRepository
    private let keychainStore: KeychainStore

    private let sessionStorageAccount = "local_auth_session"

    public init(
        userRepository: UserRepository,
        onboardingRepository: OnboardingRepository,
        analysisRepository: AnalysisRepository,
        settingsRepository: SettingsRepository,
        keychainStore: KeychainStore = KeychainStore()
    ) {
        self.userRepository = userRepository
        self.onboardingRepository = onboardingRepository
        self.analysisRepository = analysisRepository
        self.settingsRepository = settingsRepository
        self.keychainStore = keychainStore
    }

    public var isGoogleSignInAvailable: Bool {
        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clientID.isEmpty && !clientID.contains("$(")
    }

    public func restoreSession() async -> AuthSession? {
        guard let session = loadPersistedSession() else { return nil }

        do {
            switch session.provider {
            case .guest:
                break
            case .apple:
                guard let providerUserId = session.providerUserId else {
                    try await invalidateSession()
                    return nil
                }
                let state = await appleCredentialState(for: providerUserId)
                guard state == .authorized else {
                    try await invalidateSession()
                    return nil
                }
            case .google:
                guard isGoogleSignInAvailable else {
                    try await invalidateSession()
                    return nil
                }
                _ = try await restoreGoogleUser()
            }

            try settingsRepository.setCurrentUser(id: session.localUserId, provider: session.provider)
            return session
        } catch {
            try? await invalidateSession()
            return nil
        }
    }

    public func signInWithApple(result: Result<ASAuthorization, Error>) async throws -> AuthSession {
        let authorization: ASAuthorization
        switch result {
        case .success(let value):
            authorization = value
        case .failure(let error):
            if let appleError = error as? ASAuthorizationError, appleError.code == .canceled {
                throw AuthError.cancelled
            }
            throw AuthError.signInFailed(error.localizedDescription)
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidAppleCredential
        }

        let displayName = formattedName(from: credential.fullName)
        return try signInWithProvider(
            provider: .apple,
            providerUserId: credential.user,
            email: credential.email,
            displayName: displayName
        )
    }

    public func signInWithGoogle() async throws -> AuthSession {
        guard isGoogleSignInAvailable else {
            throw AuthError.googleNotConfigured
        }

        guard let presentingViewController = UIApplication.shared.topViewController else {
            throw AuthError.presentationContextMissing
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
        let googleUser = try await performGoogleSignIn(with: presentingViewController)
        let providerUserId = googleUser.userID ?? googleUser.profile?.email

        return try signInWithProvider(
            provider: .google,
            providerUserId: providerUserId,
            email: googleUser.profile?.email,
            displayName: googleUser.profile?.name
        )
    }

    public func continueAsGuest() async throws -> AuthSession {
        if let existing = loadPersistedSession(), existing.provider == .guest {
            try settingsRepository.setCurrentUser(id: existing.localUserId, provider: .guest)
            return existing
        }

        let user = try userRepository.createGuestUser()
        let session = AuthSession(
            localUserId: user.id,
            provider: .guest,
            providerUserId: nil,
            email: nil,
            displayName: user.displayName
        )
        try persistSession(session)
        return session
    }

    public func signOut() async throws {
        if GIDSignIn.sharedInstance.currentUser != nil {
            GIDSignIn.sharedInstance.signOut()
        }
        try await invalidateSession()
    }

    public func deleteAccount() async throws {
        guard let session = loadPersistedSession() else {
            throw AuthError.noActiveSession
        }

        do {
            if GIDSignIn.sharedInstance.currentUser != nil {
                GIDSignIn.sharedInstance.signOut()
            }

            try analysisRepository.deleteAnalyses(userId: session.localUserId)
            try onboardingRepository.deleteProfile(userId: session.localUserId)
            try userRepository.deleteUser(id: session.localUserId)
            try await invalidateSession()
        } catch {
            throw AuthError.accountDeletionFailed
        }
    }

    private var googleClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
    }

    private func signInWithProvider(
        provider: AuthProvider,
        providerUserId: String?,
        email: String?,
        displayName: String?
    ) throws -> AuthSession {
        let targetUser = try userRepository.findOrCreateUser(
            provider: provider,
            providerUserId: providerUserId,
            email: email,
            displayName: displayName
        )

        if let previousSession = loadPersistedSession(),
           previousSession.provider == .guest,
           previousSession.localUserId != targetUser.id {
            try analysisRepository.reassignAnalyses(from: previousSession.localUserId, to: targetUser.id)
            try onboardingRepository.reassignProfile(from: previousSession.localUserId, to: targetUser.id)
        }

        let session = AuthSession(
            localUserId: targetUser.id,
            provider: provider,
            providerUserId: providerUserId,
            email: email ?? targetUser.email,
            displayName: displayName ?? targetUser.displayName
        )
        try persistSession(session)
        return session
    }

    private func persistSession(_ session: AuthSession) throws {
        let encoder = JSONEncoder()
        guard let payload = try? encoder.encode(session) else {
            throw AuthError.sessionPersistenceFailed
        }

        do {
            try keychainStore.save(payload, account: sessionStorageAccount)
            try settingsRepository.setCurrentUser(id: session.localUserId, provider: session.provider)
        } catch {
            throw AuthError.sessionPersistenceFailed
        }
    }

    private func loadPersistedSession() -> AuthSession? {
        guard let payload = keychainStore.read(account: sessionStorageAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: payload)
    }

    private func invalidateSession() async throws {
        keychainStore.delete(account: sessionStorageAccount)
        try settingsRepository.clearCurrentUser()
    }

    private func appleCredentialState(for userId: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    private func restoreGoogleUser() async throws -> GIDGoogleUser {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let user else {
                    continuation.resume(throwing: AuthError.signInFailed("No previous Google session was found."))
                    return
                }

                continuation.resume(returning: user)
            }
        }
    }

    private func performGoogleSignIn(with presentingViewController: UIViewController) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let user = result?.user else {
                    continuation.resume(throwing: AuthError.signInFailed("Google sign-in did not return a user."))
                    return
                }

                continuation.resume(returning: user)
            }
        }
    }

    private func formattedName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let value = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
