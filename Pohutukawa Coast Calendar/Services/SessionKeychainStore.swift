import Foundation
import Security

enum SessionKeychainError: Error {
    case encodeFailed
    case decodeFailed
    case unexpectedStatus(OSStatus)
}

struct SessionKeychainStore {
    private let service = "nz.co.communitycalendar.sessions"

    func save<Value: Encodable>(_ value: Value, for account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SessionKeychainError.unexpectedStatus(status)
        }
    }

    func load<Value: Decodable>(_ type: Value.Type, for account: String) throws -> Value? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SessionKeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data else {
            throw SessionKeychainError.decodeFailed
        }

        return try JSONDecoder().decode(type, from: data)
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
