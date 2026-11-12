import Foundation
import Security

/// The private Notion and Resend keys. They're kept in the Keychain, never in the app itself,
/// so a copy of the app carries no keys. They're entered in Settings, shared with the share card
/// through a Keychain group, and carried to your other devices by iCloud Keychain.
enum Secrets {
    enum Key: String, CaseIterable {
        case notionToken = "NotionToken"
        case resendAPIKey = "ResendAPIKey"
    }

    static func value(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return clean(String(decoding: data, as: UTF8.self))
    }

    /// Saves `value`, or removes the key when it's blank. Returns whether it worked.
    @discardableResult
    static func set(_ value: String?, for key: Key) -> Bool {
        var match = baseQuery(for: key)
        match[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(match as CFDictionary)
        guard let value = value.flatMap(clean) else { return true }

        var item = baseQuery(for: key)
        item[kSecAttrSynchronizable as String] = true
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// A setting the build puts in Info.plist that isn't secret, such as the Notion database.
    static func setting(_ name: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: name) as? String).flatMap(clean)
    }

    // MARK: - Helpers

    private static func baseQuery(for key: Key) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Campfire keys",
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        // The group the app and the share card share; the build fills in the team's prefix.
        if let group = setting("KeychainGroup") { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    /// Ignores blanks and the example placeholder.
    private static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("paste-") ? nil : trimmed
    }
}
