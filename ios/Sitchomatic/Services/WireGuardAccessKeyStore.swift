import Foundation
import Security

nonisolated enum WireGuardAccessKeyStoreError: LocalizedError, Sendable {
    case invalidData
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid access key data"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        }
    }
}

nonisolated enum WireGuardAccessKeyStore {
    private static let account: String = "wireguard.access-key"

    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "Sitchomatic") + ".wireguard"
    }

    static func save(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw WireGuardAccessKeyStoreError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw WireGuardAccessKeyStoreError.unexpectedStatus(status)
        }
    }

    static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw WireGuardAccessKeyStoreError.invalidData
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw WireGuardAccessKeyStoreError.unexpectedStatus(status)
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WireGuardAccessKeyStoreError.unexpectedStatus(status)
        }
    }
}
