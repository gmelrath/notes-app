import Foundation

/// Everything the share sheet handed to Capture, normalised into one value.
struct SharedItem {
    var url: URL?
    var text: String?
    var files: [SharedFile] = []

    var isEmpty: Bool { url == nil && (text ?? "").isEmpty && files.isEmpty }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let name: String
    let fileURL: URL
    let byteCount: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// The App Group lets the share card and the main app read the same storage.
enum AppGroup {
    static let id = "group.com.gregmelrath.Capture"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// User settings, stored in the App Group so the share card can read them.
enum AppSettings {
    private static let emailKey = "emailAddress"

    static var emailAddress: String? {
        get {
            let value = AppGroup.defaults.string(forKey: emailKey)?.trimmingCharacters(in: .whitespaces)
            return value.flatMap { isValidEmail($0) ? $0 : nil }
        }
        set { AppGroup.defaults.set(newValue, forKey: emailKey) }
    }

    /// The raw text typed in Settings, valid or not.
    static var emailAddressDraft: String {
        AppGroup.defaults.string(forKey: emailKey) ?? ""
    }

    static func isValidEmail(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }
}
