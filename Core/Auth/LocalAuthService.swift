import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

@MainActor
public final class LocalAuthService: AuthService {
    private let userRepository: UserRepository
    private let onboardingDraftRepository: OnboardingDraftRepository
    private let onboardingRepository: OnboardingRepository
    private let analysisRepository: AnalysisRepository
    private let skinJourneyRepository: SkinJourneyRepository
    private let analysisPhotoStore: AnalysisPhotoStoring
    private let settingsRepository: SettingsRepository
    private let backendSessionService: BackendSessionService
    private let keychainStore: KeychainStore

    private let sessionStorageAccount = "local_auth_session"
    private let sessionStorageDefaultsKey = "local_auth_session_fallback"
    private var lastGuestBackendSessionError: String?

    public init(
        userRepository: UserRepository,
        onboardingDraftRepository: OnboardingDraftRepository,
        onboardingRepository: OnboardingRepository,
        analysisRepository: AnalysisRepository,
        skinJourneyRepository: SkinJourneyRepository,
        analysisPhotoStore: AnalysisPhotoStoring = FileSystemAnalysisPhotoStore(),
        settingsRepository: SettingsRepository,
        backendSessionService: BackendSessionService = BackendSessionService(),
        keychainStore: KeychainStore = KeychainStore()
    ) {
        self.userRepository = userRepository
        self.onboardingDraftRepository = onboardingDraftRepository
        self.onboardingRepository = onboardingRepository
        self.analysisRepository = analysisRepository
        self.skinJourneyRepository = skinJourneyRepository
        self.analysisPhotoStore = analysisPhotoStore
        self.settingsRepository = settingsRepository
        self.backendSessionService = backendSessionService
        self.keychainStore = keychainStore
    }

    public var isGoogleSignInAvailable: Bool {
        let clientID = googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clientID.isEmpty && !clientID.contains("$(")
    }

    public var hasStoredBackendSession: Bool {
        backendSessionService.hasStoredSession
    }

    public var lastGuestBackendSessionErrorDescription: String? {
        lastGuestBackendSessionError
    }

    public func restoreSession() async -> AuthSession? {
        guard let session = loadPersistedSession() else { return nil }

        switch session.provider {
        case .guest:
            let restoredGuestSession = await restoreGuestSession(
                existingLocalUserId: session.localUserId,
                displayName: session.displayName
            )
            try? persistSession(restoredGuestSession)
            return restoredGuestSession
        case .apple:
            do {
                clearGuestBackendSessionError()
                guard let providerUserId = session.providerUserId else {
                    try await invalidateSession()
                    return nil
                }
                let state = await appleCredentialState(for: providerUserId)
                guard state == .authorized else {
                    try await invalidateSession()
                    return nil
                }
                _ = try await restoreBackendSessionIfNeeded(for: session)
                synchronizeCurrentUser(session)
                return session
            } catch {
                try? await invalidateSession()
                return nil
            }
        case .google:
            do {
                clearGuestBackendSessionError()
                guard isGoogleSignInAvailable else {
                    try await invalidateSession()
                    return nil
                }
                _ = try await restoreGoogleUser()
                _ = try await restoreBackendSessionIfNeeded(for: session)
                synchronizeCurrentUser(session)
                return session
            } catch {
                try? await invalidateSession()
                return nil
            }
        }
    }

    public func continueAsGuestForBootstrap() async throws -> AuthSession {
        if let existing = loadPersistedSession(), existing.provider == .guest {
            let session = await restoreGuestSession(
                existingLocalUserId: existing.localUserId,
                displayName: existing.displayName
            )
            try persistSession(session)
            return session
        }

        let user = try userRepository.createGuestUser()
        let session = await restoreGuestSession(
            existingLocalUserId: user.id,
            displayName: user.displayName
        )
        try persistSession(session)
        return session
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

        guard
            let providerToken = normalizedCredentialString(from: credential.identityToken)
        else {
            throw AuthError.missingProviderToken
        }

        let displayName = formattedName(from: credential.fullName)
        return try await signInWithProvider(
            provider: .apple,
            providerToken: providerToken,
            providerAuthorizationCode: normalizedCredentialString(from: credential.authorizationCode),
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
        var googleUser = try await performGoogleSignIn(with: presentingViewController)
        googleUser = try await refreshGoogleUserTokensIfNeeded(googleUser)
        guard let providerToken = googleUser.idToken?.tokenString, !providerToken.isEmpty else {
            throw AuthError.missingProviderToken
        }
        let providerUserId = googleUser.userID ?? googleUser.profile?.email

        return try await signInWithProvider(
            provider: .google,
            providerToken: providerToken,
            providerUserId: providerUserId,
            email: googleUser.profile?.email,
            displayName: googleUser.profile?.name
        )
    }

    public func continueAsGuest() async throws -> AuthSession {
        if let existing = loadPersistedSession(), existing.provider == .guest {
            let session = await restoreGuestSession(
                existingLocalUserId: existing.localUserId,
                displayName: existing.displayName
            )
            try persistSession(session)
            return session
        }

        let user = try userRepository.createGuestUser()
        let session = await restoreGuestSession(
            existingLocalUserId: user.id,
            displayName: user.displayName
        )
        try persistSession(session)
        return session
    }

    private func guestSession(existingLocalUserId localUserId: String, displayName: String?) async throws -> AuthSession {
        guard backendSessionService.isConfigured else {
            let error = AuthError.backendNotConfigured
            recordGuestBackendSessionError(error)
            backendSessionService.clearLocalSession()
            throw error
        }

        do {
            let backendSession = try await backendSessionService.exchangeSession(
                provider: .guest,
                providerToken: "dev-guest",
                providerUserID: localUserId,
                email: nil,
                displayName: displayName
            )
            clearGuestBackendSessionError()
            return makeGuestSession(
                localUserId: localUserId,
                displayName: displayName,
                remoteUserId: backendSession.userID
            )
        } catch {
            recordGuestBackendSessionError(error)
            backendSessionService.clearLocalSession()
            throw error
        }
    }

    private func restoreGuestSession(existingLocalUserId localUserId: String, displayName: String?) async -> AuthSession {
        do {
            return try await guestSession(
                existingLocalUserId: localUserId,
                displayName: displayName
            )
        } catch {
            recordGuestBackendSessionError(error)
            return makeGuestSession(
                localUserId: localUserId,
                displayName: displayName,
                remoteUserId: nil
            )
        }
    }

    private func makeGuestSession(
        localUserId: String,
        displayName: String?,
        remoteUserId: String?
    ) -> AuthSession {
        AuthSession(
            localUserId: localUserId,
            provider: .guest,
            providerUserId: localUserId,
            email: nil,
            displayName: displayName,
            remoteUserId: remoteUserId
        )
    }

    public func signOut() async throws {
        if GIDSignIn.sharedInstance.currentUser != nil {
            GIDSignIn.sharedInstance.signOut()
        }
        try? await backendSessionService.revokeCurrentSession()
        try await invalidateSession()
    }

    public func deleteAccount() async throws {
        guard let session = loadPersistedSession() else {
            throw AuthError.noActiveSession
        }

        let localAnalyses = try? analysisRepository.fetchAllAnalyses(userId: session.localUserId)
        let localPhotoPaths = localAnalyses?.compactMap(\.localImageRelativePath) ?? []

        do {
            if GIDSignIn.sharedInstance.currentUser != nil {
                GIDSignIn.sharedInstance.signOut()
            }

            if session.usesRemoteBackend {
                try await backendSessionService.deleteCurrentAccount()
            } else {
                backendSessionService.clearLocalSession()
            }

            try analysisRepository.deleteAnalyses(userId: session.localUserId)
            for relativePath in Set(localPhotoPaths) {
                try? analysisPhotoStore.deletePhoto(relativePath: relativePath)
            }
            try onboardingDraftRepository.deleteDraft(userId: session.localUserId)
            try skinJourneyRepository.deleteLogs(userId: session.localUserId)
            try onboardingRepository.deleteProfile(userId: session.localUserId)
            try userRepository.deleteUser(id: session.localUserId)
            try await invalidateSession()
        } catch {
            throw AuthError.accountDeletionFailed
        }
    }

    private var googleClientID: String {
        AppConfig.googleClientID()
    }

    private func signInWithProvider(
        provider: AuthProvider,
        providerToken: String?,
        providerAuthorizationCode: String? = nil,
        providerUserId: String?,
        email: String?,
        displayName: String?
    ) async throws -> AuthSession {
        let backendSession: BackendSession?
        if provider == .guest {
            backendSession = nil
            backendSessionService.clearLocalSession()
        } else {
            clearGuestBackendSessionError()
            guard backendSessionService.isConfigured else {
                throw AuthError.backendNotConfigured
            }
            guard let providerToken, !providerToken.isEmpty else {
                throw AuthError.missingProviderToken
            }
            backendSession = try await backendSessionService.exchangeSession(
                provider: provider,
                providerToken: providerToken,
                providerAuthorizationCode: providerAuthorizationCode,
                providerUserID: providerUserId,
                email: email,
                displayName: displayName
            )
        }

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
            try onboardingDraftRepository.reassignDraft(from: previousSession.localUserId, to: targetUser.id)
            try skinJourneyRepository.reassignLogs(from: previousSession.localUserId, to: targetUser.id)
            try onboardingRepository.reassignProfile(from: previousSession.localUserId, to: targetUser.id)
        }

        let session = AuthSession(
            localUserId: targetUser.id,
            provider: provider,
            providerUserId: providerUserId,
            email: email ?? targetUser.email,
            displayName: displayName ?? targetUser.displayName,
            remoteUserId: backendSession?.userID
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
        } catch {
            UserDefaults.standard.set(payload, forKey: sessionStorageDefaultsKey)
            synchronizeCurrentUser(session)
            return
        }

        UserDefaults.standard.removeObject(forKey: sessionStorageDefaultsKey)
        synchronizeCurrentUser(session)
    }

    private func loadPersistedSession() -> AuthSession? {
        if let payload = keychainStore.read(account: sessionStorageAccount) {
            return try? JSONDecoder().decode(AuthSession.self, from: payload)
        }

        guard let payload = UserDefaults.standard.data(forKey: sessionStorageDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: payload)
    }

    private func invalidateSession() async throws {
        keychainStore.delete(account: sessionStorageAccount)
        UserDefaults.standard.removeObject(forKey: sessionStorageDefaultsKey)
        backendSessionService.clearLocalSession()
        clearGuestBackendSessionError()
        try settingsRepository.clearCurrentUser()
    }

    private func restoreBackendSessionIfNeeded(for session: AuthSession) async throws -> BackendSession? {
        guard session.usesRemoteBackend else {
            backendSessionService.clearLocalSession()
            return nil
        }
        guard backendSessionService.isConfigured else {
            throw AuthError.backendNotConfigured
        }
        return try await backendSessionService.restoreSession(for: session)
    }

    private func synchronizeCurrentUser(_ session: AuthSession) {
        do {
            try settingsRepository.setCurrentUser(id: session.localUserId, provider: session.provider)
        } catch {
            #if DEBUG
            print("LocalAuthService: failed to sync current user settings: \(error)")
            #endif
        }
    }

    private func recordGuestBackendSessionError(_ error: Error) {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            lastGuestBackendSessionError = localized
            return
        }
        lastGuestBackendSessionError = error.localizedDescription
    }

    private func clearGuestBackendSessionError() {
        lastGuestBackendSessionError = nil
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

    private func refreshGoogleUserTokensIfNeeded(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let refreshedUser else {
                    continuation.resume(throwing: AuthError.missingProviderToken)
                    return
                }
                continuation.resume(returning: refreshedUser)
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

    private func normalizedCredentialString(from data: Data?) -> String? {
        guard let data, let value = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
