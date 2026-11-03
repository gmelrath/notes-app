import CloudKit
import Foundation

/// Mirrors the history to your private iCloud database, so iPhone and iPad share one list.
/// The JSON file in the App Group stays what the screens read: local changes queue up and are
/// uploaded when there's a connection, and other devices' changes are pulled into the file.
/// The app and the share card both sync, each remembering its own place in the change feed.
actor CloudHistory {
    static let shared = CloudHistory()

    private let container = CKContainer(identifier: "iCloud.com.gregmelrath.Campfire")
    private let zoneID = CKRecordZone.ID(zoneName: "History")
    private var isSyncing = false
    private var syncAgain = false

    /// Uploads queued changes, then (unless `includePull` is false) fetches other devices' changes.
    /// Returns whether the local history changed. Without an iCloud account or a connection it
    /// does nothing, and queued changes wait for the next sync.
    @discardableResult
    func sync(includePull: Bool = true) async -> Bool {
        if isSyncing {
            syncAgain = true
            return false
        }
        isSyncing = true
        defer { isSyncing = false }

        var changed = false
        repeat {
            syncAgain = false
            guard (try? await container.accountStatus()) == .available else { return changed }
            do {
                try await prepare()
                try await upload()
                if includePull, try await fetchChanges() { changed = true }
            } catch {
                handle(error)
                return changed
            }
        } while syncAgain
        return changed
    }

    // MARK: - Steps

    /// Creates the iCloud zone and change subscription once, and queues this device's existing history.
    private func prepare() async throws {
        guard !AppGroup.defaults.bool(forKey: Keys.ready) else { return }
        try await withDatabase { database in
            let zones = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            _ = try zones.saveResults[zoneID]?.get()

            // Lets iCloud wake the app when another device changes something.
            let subscription = CKDatabaseSubscription(subscriptionID: "history")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            let subscriptions = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            _ = try subscriptions.saveResults[subscription.subscriptionID]?.get()
        }
        CloudQueue.markSaved(CaptureStore.load().map(\.id))
        AppGroup.defaults.set(true, forKey: Keys.ready)
    }

    private func upload() async throws {
        let startedAt = Date()
        let saves = CloudQueue.saves
        let deletes = CloudQueue.deletes
        guard !saves.isEmpty || !deletes.isEmpty else { return }

        let local = Dictionary(CaptureStore.load().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A queued save whose entry is gone has nothing to upload; its delete is queued instead.
        CloudQueue.clear(saves.filter { local[$0] == nil }, changedBefore: startedAt)
        let records = saves.compactMap { local[$0] }.compactMap(record(for:))
        let recordIDs = deletes.map(recordID(for:))

        for start in stride(from: 0, to: max(records.count, recordIDs.count), by: 200) {
            let saving = Array(records[min(start, records.count)..<min(start + 200, records.count)])
            let deleting = Array(recordIDs[min(start, recordIDs.count)..<min(start + 200, recordIDs.count)])
            let results = try await withDatabase { database in
                try await database.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys, atomically: false)
            }

            var done: [Capture.ID] = []
            for (id, result) in results.saveResults {
                if case .success = result, let uuid = UUID(uuidString: id.recordName) { done.append(uuid) }
            }
            for (id, result) in results.deleteResults {
                guard let uuid = UUID(uuidString: id.recordName) else { continue }
                switch result {
                case .success: done.append(uuid)
                case .failure(let error as CKError) where error.code == .unknownItem: done.append(uuid)
                case .failure: break
                }
            }
            CloudQueue.clear(done, changedBefore: startedAt)
        }
    }

    private func fetchChanges() async throws -> Bool {
        var token = loadToken()
        var saved: [Capture] = []
        var deleted = Set<Capture.ID>()
        var moreComing = true

        while moreComing {
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion],
                          changeToken: CKServerChangeToken,
                          moreComing: Bool)
            do {
                changes = try await withDatabase { [token] database in
                    try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                }
            } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
                // Too long since the last sync: start again from the beginning.
                token = nil
                saved = []
                deleted = []
                continue
            }
            for result in changes.modificationResultsByID.values {
                if case .success(let modification) = result, let capture = capture(from: modification.record) {
                    saved.append(capture)
                }
            }
            for deletion in changes.deletions {
                if let id = UUID(uuidString: deletion.recordID.recordName) { deleted.insert(id) }
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }

        let changed = CaptureStore.merge(saved: saved, deleted: deleted, keeping: CloudQueue.pendingIDs)
        saveToken(token)
        return changed
    }

    private func handle(_ error: Error) {
        guard let error = error as? CKError else { return }
        let zoneGone: Set<CKError.Code> = [.zoneNotFound, .userDeletedZone]
        let partialZoneGone = error.partialErrorsByItemID?.values.contains { zoneGone.contains(($0 as? CKError)?.code ?? .internalError) } ?? false
        if zoneGone.contains(error.code) || partialZoneGone {
            // The iCloud data was removed: set it up again and re-upload this device's history.
            AppGroup.defaults.set(false, forKey: Keys.ready)
            for key in AppGroup.defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.tokenPrefix) {
                AppGroup.defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Helpers

    /// Requests give up after 15 seconds, so a poor connection can't hold the share card open.
    private func withDatabase<T: Sendable>(_ body: @Sendable (CKDatabase) async throws -> T) async throws -> T {
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = 15
        configuration.qualityOfService = .userInitiated
        return try await container.privateCloudDatabase.configuredWith(configuration: configuration, body: body)
    }

    private func recordID(for id: Capture.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Each entry is stored whole, as JSON, so new fields sync without changing the iCloud schema.
    private func record(for capture: Capture) -> CKRecord? {
        guard let data = try? CaptureStore.encoder.encode(capture) else { return nil }
        let record = CKRecord(recordType: "Capture", recordID: recordID(for: capture.id))
        record["payload"] = data as NSData
        record["date"] = capture.date as NSDate
        return record
    }

    private func capture(from record: CKRecord) -> Capture? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? CaptureStore.decoder.decode(Capture.self, from: data)
    }

    /// The app and the share card each keep their own token, so neither skips changes the other fetched.
    private var tokenKey: String { Keys.tokenPrefix + (Bundle.main.bundleIdentifier ?? "app") }

    private func loadToken() -> CKServerChangeToken? {
        guard let data = AppGroup.defaults.data(forKey: tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken?) {
        let data = token.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        AppGroup.defaults.set(data, forKey: tokenKey)
    }

    private enum Keys {
        static let ready = "cloudReady"
        static let tokenPrefix = "cloudToken."
    }
}

/// Local changes waiting to reach iCloud. Kept in the App Group, so if the share card closes
/// before its upload finishes, the app sends it later.
enum CloudQueue {
    private static let savesKey = "cloudPendingSaves"
    private static let deletesKey = "cloudPendingDeletes"

    static var saves: [Capture.ID] { ids(in: savesKey) }
    static var deletes: [Capture.ID] { ids(in: deletesKey) }
    static var pendingIDs: Set<Capture.ID> { Set(saves + deletes) }

    static func markSaved(_ ids: some Sequence<Capture.ID>) {
        change(savesKey) { entries in
            for id in ids { entries[id.uuidString] = Date.now.timeIntervalSince1970 }
        }
    }

    static func markDeleted(_ ids: some Sequence<Capture.ID>) {
        let ids = Array(ids)
        change(savesKey) { entries in
            for id in ids { entries[id.uuidString] = nil }
        }
        change(deletesKey) { entries in
            for id in ids { entries[id.uuidString] = Date.now.timeIntervalSince1970 }
        }
    }

    /// Clears uploaded entries, except ones changed again while the upload was under way.
    static func clear(_ ids: [Capture.ID], changedBefore date: Date) {
        let cutoff = date.timeIntervalSince1970
        for key in [savesKey, deletesKey] {
            change(key) { entries in
                for id in ids where (entries[id.uuidString] ?? 0) < cutoff {
                    entries[id.uuidString] = nil
                }
            }
        }
    }

    private static func ids(in key: String) -> [Capture.ID] {
        let entries = AppGroup.defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        return entries.keys.compactMap(UUID.init(uuidString:))
    }

    private static func change(_ key: String, _ body: (inout [String: Double]) -> Void) {
        var entries = AppGroup.defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        body(&entries)
        AppGroup.defaults.set(entries, forKey: key)
    }
}
