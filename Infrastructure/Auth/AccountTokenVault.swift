import Foundation
import Security

protocol AccountTokenVault {
    func token(for accountID: UUID) -> String?
    func setToken(_ token: String, for accountID: UUID)
    func removeToken(for accountID: UUID)
}

final class InMemoryAccountTokenVault: AccountTokenVault {
    private var storage: [UUID: String] = [:]

    func token(for accountID: UUID) -> String? {
        storage[accountID]
    }

    func setToken(_ token: String, for accountID: UUID) {
        storage[accountID] = token
    }

    func removeToken(for accountID: UUID) {
        storage.removeValue(forKey: accountID)
    }
}

final class KeychainAccountTokenVault: AccountTokenVault {
    private let service = "com.aiagentpool.account-token"

    func token(for accountID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func setToken(_ token: String, for accountID: UUID) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func removeToken(for accountID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
