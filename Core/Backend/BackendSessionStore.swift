import Foundation

public protocol BackendSessionStoring: AnyObject {
    func save(_ session: BackendSession) throws
    func read() -> BackendSession?
    func delete()
}

public final class BackendSessionStore: BackendSessionStoring {
    private let keychainStore: KeychainStore
    private let account = "backend_app_session"

    public init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
    }

    public func save(_ session: BackendSession) throws {
        let payload = try JSONEncoder.backendEncoder.encode(session)
        try keychainStore.save(payload, account: account)
    }

    public func read() -> BackendSession? {
        guard let payload = keychainStore.read(account: account) else {
            return nil
        }
        return try? JSONDecoder.backendDecoder.decode(BackendSession.self, from: payload)
    }

    public func delete() {
        keychainStore.delete(account: account)
    }
}

public final class InMemoryBackendSessionStore: BackendSessionStoring {
    private var session: BackendSession?

    public init() {}

    public func save(_ session: BackendSession) throws {
        self.session = session
    }

    public func read() -> BackendSession? {
        session
    }

    public func delete() {
        session = nil
    }
}
