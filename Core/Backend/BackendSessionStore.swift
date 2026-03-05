import Foundation

public final class BackendSessionStore {
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
