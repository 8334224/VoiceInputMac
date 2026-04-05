import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing small secret strings
/// (e.g. API keys) instead of writing them to UserDefaults / plist files.
enum KeychainHelper {

    // MARK: - Public API

    /// Save or update a string value in the Keychain.
    @discardableResult
    static func save(key: String, value: String, service: String = defaultService) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update first; if the item doesn't exist yet, add it.
        let query = baseQuery(key: key, service: service)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            return updateStatus == errSecSuccess
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
    }

    /// Read a string value from the Keychain. Returns `nil` when not found.
    static func read(key: String, service: String = defaultService) -> String? {
        var query = baseQuery(key: key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    @discardableResult
    static func delete(key: String, service: String = defaultService) -> Bool {
        let query = baseQuery(key: key, service: service)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Internals

    private static let defaultService = "com.voiceinputmac.settings"

    private static func baseQuery(key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
