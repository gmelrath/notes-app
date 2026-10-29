import Foundation

/// Reads private keys that the build copies into Info.plist from Config/Secrets.xcconfig.
enum Secrets {
    /// The value for `key`, ignoring blanks and the example placeholder.
    static func value(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("paste-") ? nil : trimmed
    }
}
