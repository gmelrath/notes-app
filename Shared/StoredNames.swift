import Foundation

// Every name the app stores data under. These names are written on your devices, in iCloud and in
// the Keychain, so renaming one makes the app lose what was saved under the old name, without any
// error. Never change a value here; add a new name instead. Tests/StoredNameTests.swift pins them all.

/// Settings and sync progress kept on the device.
enum StoredName: String, CaseIterable {
    // Settings, in the App Group so the share card can read them.
    case emailAddress
    case settingsChangedAt
    case settingsPendingUpload
    // iCloud sync progress, in the App Group.
    case cloudReady
    case cloudPendingSaves
    case cloudPendingDeletes
    // Appearance, in the app's own settings.
    case titleFont

    /// Each process keeps its own iCloud change token, under this prefix plus its bundle ID.
    static let cloudTokenPrefix = "cloudToken."
}

/// Names in iCloud's database. They're part of its schema, so existing records are only found
/// under these exact names.
enum CloudName {
    static let zone = "History"
    static let subscription = "history"

    /// One history entry, stored whole as JSON.
    enum Capture {
        static let type = "Capture"
        static let payload = "payload"
        static let date = "date"
    }

    /// The settings that sync between devices, as a single record.
    enum Settings {
        static let type = "Settings"
        static let recordName = "settings"
        static let email = "email"
        static let changedAt = "changedAt"
    }
}
