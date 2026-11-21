import Foundation
import Testing
@testable import Stowaway

/// Every name and value the app has already saved on devices, in iCloud and in the Keychain.
/// If one of these tests fails, a rename would make the app lose data stored under the old name:
/// put the old value back and add a new name instead.
@Suite("Stored names never change")
struct StoredNameTests {
    @Test func deviceSettings() {
        #expect(StoredName.allCases.map(\.rawValue) == [
            "emailAddress", "settingsChangedAt", "settingsPendingUpload",
            "cloudReady", "cloudPendingSaves", "cloudPendingDeletes",
            "titleFont", "notionColumns",
        ])
        #expect(StoredName.cloudTokenPrefix == "cloudToken.")
        #expect(TitleFont.storageKey == "titleFont")
    }

    @Test func noTwoSettingsShareAName() {
        let names = StoredName.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        #expect(!names.contains { $0.hasPrefix(StoredName.cloudTokenPrefix) })
    }

    @Test func iCloudNames() {
        #expect(CloudName.zone == "History")
        #expect(CloudName.subscription == "history")
        #expect(CloudName.Capture.type == "Capture")
        #expect(CloudName.Capture.payload == "payload")
        #expect(CloudName.Capture.date == "date")
        #expect(CloudName.Settings.type == "Settings")
        #expect(CloudName.Settings.recordName == "settings")
        #expect(CloudName.Settings.email == "email")
        #expect(CloudName.Settings.changedAt == "changedAt")
    }

    @Test func keychainNames() {
        #expect(Secrets.service == "Campfire keys")
        #expect(Secrets.Key.allCases.map(\.rawValue) == ["NotionToken", "ResendAPIKey"])
    }

    @Test func savedValues() {
        // The title-font choice is saved as its raw value, and history entries save the destination's.
        #expect(TitleFont.allCases.map(\.rawValue) == ["sansSerif", "serif"])
        #expect(Destination.allCases.map(\.rawValue) == ["Notion", "Email"])
    }

    @Test func historyEntryFieldNames() throws {
        // A history entry with every field filled in: its field names are what's saved in the
        // history file and in iCloud.
        let full = Capture(title: "t", url: URL(string: "https://example.com"), canonicalURL: URL(string: "https://example.com"),
                           summary: "s", note: "n", text: "x", fileNames: ["f"], sentFrom: "iPhone", isPost: true,
                           destination: .notion, status: .failed, errorMessage: "e")
        let entry = try #require(try JSONSerialization.jsonObject(with: CaptureStore.encoder.encode(full)) as? [String: Any])
        #expect(Set(entry.keys) == [
            "id", "date", "title", "url", "canonicalURL", "summary", "note", "text", "fileNames",
            "sentFrom", "isPost", "destination", "status", "errorMessage",
        ])
        #expect(Capture.Status.sent.rawValue == "sent" && Capture.Status.failed.rawValue == "failed")
    }
}
