import Foundation
import Security

// MARK: - Keychain Store
// Unified Keychain wrapper for all secure storage: auth tokens, SAP credentials, etc.

enum KeychainStore {

    // MARK: - Generic Operations

    @discardableResult
    static func save(_ data: Data, for key: String, service: String? = nil) -> Bool {
        let base = baseQuery(key: key, service: service)
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load(_ key: String, service: String? = nil) -> Data? {
        var query = baseQuery(key: key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    static func delete(_ key: String, service: String? = nil) -> Bool {
        let query = baseQuery(key: key, service: service)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - String Convenience

    @discardableResult
    static func saveString(_ value: String, for key: String, service: String? = nil) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, for: key, service: service)
    }

    static func loadString(_ key: String, service: String? = nil) -> String? {
        guard let data = load(key, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Auth Token Helpers

    private static let authService = "com.bluefunda.ai"
    private static let authTokensKey = "auth_tokens"

    static func saveAuthTokens(
        refreshToken: String,
        realm: String,
        expiresAt: Date?
    ) {
        let payload: [String: Any] = [
            "refreshToken": refreshToken,
            "realm": realm,
            "expiresAt": expiresAt?.timeIntervalSince1970 ?? 0
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            save(data, for: authTokensKey, service: authService)
        }
    }

    static func loadAuthTokens() -> (refreshToken: String, realm: String, expiresAt: Date?)? {
        guard let data = load(authTokensKey, service: authService),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let refreshToken = json["refreshToken"] as? String,
              let realm = json["realm"] as? String else {
            return nil
        }
        let ts = json["expiresAt"] as? TimeInterval ?? 0
        let expiresAt: Date? = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return (refreshToken, realm, expiresAt)
    }

    static func clearAuthTokens() {
        delete(authTokensKey, service: authService)
    }

    // MARK: - Private

    private static func baseQuery(key: String, service: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String:   kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        if let service = service {
            query[kSecAttrService as String] = service
        }
        return query
    }
}
