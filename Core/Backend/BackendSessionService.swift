import Foundation

public final class BackendSessionService {
    private let client: ConvexBackendClient
    private let store: BackendSessionStore

    public init(
        client: ConvexBackendClient = ConvexBackendClient(),
        store: BackendSessionStore = BackendSessionStore()
    ) {
        self.client = client
        self.store = store
    }

    public var isConfigured: Bool {
        client.isConfigured
    }

    public func exchangeSession(
        provider: AuthProvider,
        providerToken: String,
        providerUserID: String?,
        email: String?,
        displayName: String?
    ) async throws -> BackendSession {
        let session = try await client.exchangeSession(
            provider: provider,
            providerToken: providerToken,
            providerUserID: providerUserID,
            email: email,
            displayName: displayName
        )
        try store.save(session)
        return session
    }

    public func restoreSession(for authSession: AuthSession) async throws -> BackendSession? {
        guard authSession.usesRemoteBackend else {
            store.delete()
            return nil
        }
        guard var current = store.read() else {
            throw BackendClientError.missingSession
        }
        if let remoteUserId = authSession.remoteUserId, current.userID != remoteUserId {
            throw BackendClientError.missingSession
        }
        if current.expiresAt.timeIntervalSinceNow <= 7 * 24 * 60 * 60 {
            current = try await client.refreshSession(sessionToken: current.sessionToken)
            try store.save(current)
        }
        return current
    }

    public func currentSession() -> BackendSession? {
        store.read()
    }

    public func requireCurrentSession() throws -> BackendSession {
        guard let session = store.read() else {
            throw BackendClientError.missingSession
        }
        return session
    }

    public func revokeCurrentSession() async throws {
        guard let session = store.read() else {
            store.delete()
            return
        }
        do {
            try await client.revokeSession(sessionToken: session.sessionToken)
        } catch BackendClientError.unauthorized {
            // Treat an already invalid backend session as revoked.
        }
        store.delete()
    }

    public func clearLocalSession() {
        store.delete()
    }

    public func deleteCurrentAccount() async throws {
        guard let session = store.read() else {
            throw BackendClientError.missingSession
        }
        try await client.deleteAccount(sessionToken: session.sessionToken)
        store.delete()
    }
}
