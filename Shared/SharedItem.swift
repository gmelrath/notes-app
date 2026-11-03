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

/// User settings. Kept in iCloud so iPhone and iPad match, with a copy in the App Group
/// for when iCloud isn't available.
enum AppSettings {
    private static let emailKey = "emailAddress"
    private static var cloud: NSUbiquitousKeyValueStore { .default }

    static var emailAddress: String? {
        get {
            let value = emailAddressDraft.trimmingCharacters(in: .whitespaces)
            return isValidEmail(value) ? value : nil
        }
        set {
            AppGroup.defaults.set(newValue, forKey: emailKey)
            if let newValue { cloud.set(newValue, forKey: emailKey) } else { cloud.removeObject(forKey: emailKey) }
        }
    }

    /// The raw text typed in Settings, valid or not.
    static var emailAddressDraft: String {
        cloud.string(forKey: emailKey) ?? AppGroup.defaults.string(forKey: emailKey) ?? ""
    }

    /// Called at launch: copies an address set before iCloud sync existed up to iCloud,
    /// and keeps the local copy in step with changes made on other devices.
    static func startSyncing() {
        cloud.synchronize()
        if cloud.string(forKey: emailKey) == nil, let local = AppGroup.defaults.string(forKey: emailKey) {
            cloud.set(local, forKey: emailKey)
        }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { _ in
            AppGroup.defaults.set(cloud.string(forKey: emailKey), forKey: emailKey)
        }
    }

    static func isValidEmail(_ text: String) -> Bool {
        text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }
}
