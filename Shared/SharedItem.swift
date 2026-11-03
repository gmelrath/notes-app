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
    // Still named for Capture, the app's original name: changing it would orphan the history already on the phone.
    static let id = "group.com.gregmelrath.Capture"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

/// User settings, stored in the App Group so the share card can read them, and synced
/// between devices through iCloud along with the history.
enum AppSettings {
    private static let emailKey = "emailAddress"
    private static let changedAtKey = "settingsChangedAt"
    private static let pendingKey = "settingsPendingUpload"

    static var emailAddress: String? {
        get {
            let value = AppGroup.defaults.string(forKey: emailKey)?.trimmingCharacters(in: .whitespaces)
            return value.flatMap { isValidEmail($0) ? $0 : nil }
        }
        set {
            AppGroup.defaults.set(newValue, forKey: emailKey)
            AppGroup.defaults.set(Date.now, forKey: changedAtKey)
            AppGroup.defaults.set(true, forKey: pendingKey)
        }
    }

    /// The raw text typed in Settings, valid or not.
    static var emailAddressDraft: String {
        AppGroup.defaults.string(forKey: emailKey) ?? ""
    }

    /// A local change iCloud hasn't received yet. An address saved before syncing existed counts as one.
    static var pendingUpload: (email: String?, changedAt: Date)? {
        let defaults = AppGroup.defaults
        if defaults.object(forKey: changedAtKey) == nil, defaults.string(forKey: emailKey) != nil {
            defaults.set(Date.now, forKey: changedAtKey)
            defaults.set(true, forKey: pendingKey)
        }
        guard defaults.bool(forKey: pendingKey), let changedAt = defaults.object(forKey: changedAtKey) as? Date else { return nil }
        return (defaults.string(forKey: emailKey), changedAt)
    }

    static func markUploaded(changedAt: Date) {
        // Only if nothing changed again while uploading.
        if (AppGroup.defaults.object(forKey: changedAtKey) as? Date) == changedAt {
            AppGroup.defaults.set(false, forKey: pendingKey)
        }
    }

    /// Takes the other device's settings if they're newer. Returns whether anything changed.
    static func applyFromCloud(email: String?, changedAt: Date) -> Bool {
        let defaults = AppGroup.defaults
        if let local = defaults.object(forKey: changedAtKey) as? Date, local >= changedAt { return false }
        let changed = defaults.string(forKey: emailKey) != email
        defaults.set(email, forKey: emailKey)
        defaults.set(changedAt, forKey: changedAtKey)
        defaults.set(false, forKey: pendingKey)
        return changed
    }

    static func isValidEmail(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }
}
