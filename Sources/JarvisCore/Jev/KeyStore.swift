import Foundation
import Security

/// Where the TypeSafe key lives. An app started at login does not see shell variables, so the key is kept in the Keychain.
public enum KeyStore {
    static let service = "Jarvis"
    static let account = "typesafe-api-key"

    /// The key from the TYPESAFE_API_KEY variable when it is set (development, tests), otherwise from the Keychain.
    public static func jevKey() -> String? {
        if let fromShell = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !fromShell.isEmpty { return fromShell }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// Saves the key in the login Keychain, replacing an earlier one. Run from the Jarvis program itself, so that
    /// Jarvis is the application the Keychain trusts to read it back.
    @discardableResult
    public static func store(_ key: String) -> Bool {
        let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                       kSecAttrAccount as String: account]
        SecItemDelete(identity as CFDictionary)
        var item = identity
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Jarvis: TypeSafe API key"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
