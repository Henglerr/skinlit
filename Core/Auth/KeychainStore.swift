import Foundation
import Security

public final class KeychainStore {
    public enum KeychainError: Error {
        case operationFailed(OSStatus)
        case encodingFailed
    }

    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.skinlit.SkinLit") {
        self.service = service
    }

    public func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
#if targetEnvironment(simulator)
            UserDefaults.standard.set(data, forKey: fallbackKey(for: account))
            return
#else
            throw KeychainError.operationFailed(status)
#endif
        }

#if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: fallbackKey(for: account))
#endif
    }

    public func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
#if targetEnvironment(simulator)
            return UserDefaults.standard.data(forKey: fallbackKey(for: account))
#else
            return nil
#endif
        }

        return item as? Data
    }

    public func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
#if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: fallbackKey(for: account))
#endif
    }

    private func fallbackKey(for account: String) -> String {
        "sim-keychain-fallback.\(service).\(account)"
    }
}
