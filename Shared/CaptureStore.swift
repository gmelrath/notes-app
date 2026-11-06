import Foundation

/// The history log, kept as a JSON file in the App Group so the share card and the app share it.
/// Reads and writes are coordinated because the card and the app can run at the same time.
enum CaptureStore {
    private static var fileURL: URL {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("captures.json")
    }

    /// Newest first.
    static func load() -> [Capture] {
        var result: [Capture] = []
        coordinate(writing: false) { url in result = read(url)?.captures ?? [] }
        return result
    }

    static func save(_ capture: Capture) {
        update { file in
            file.remove([capture.id])
            file.captures.insert(capture, at: 0)
        }
        CloudQueue.markSaved([capture.id])
    }

    static func delete(ids: Set<Capture.ID>) {
        update { file in file.remove(ids) }
        CloudQueue.markDeleted(ids)
    }

    /// Applies changes from other devices. Entries with local changes still waiting to upload are
    /// left alone, so they aren't overwritten by an older copy. `unreadable` are entries from a newer
    /// version of Campfire; they're kept for when this one is updated. Returns whether anything changed.
    static func merge(saved: [Capture], unreadable: [Data] = [], deleted: Set<Capture.ID>, keeping pending: Set<Capture.ID>) -> Bool {
        guard !saved.isEmpty || !unreadable.isEmpty || !deleted.isEmpty else { return false }
        var changed = false
        update { file in
            for capture in saved where !pending.contains(capture.id) {
                if let index = file.captures.firstIndex(where: { $0.id == capture.id }) {
                    if file.captures[index] != capture {
                        file.captures[index] = capture
                        changed = true
                    }
                } else {
                    file.remove([capture.id])
                    file.captures.append(capture)
                    changed = true
                }
            }
            for data in unreadable {
                guard let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = HistoryFile.id(of: entry), !pending.contains(id) else { continue }
                if file.captures.contains(where: { $0.id == id }) { changed = true }
                file.remove([id])
                file.unreadable.append(entry)
            }
            let countBefore = file.captures.count
            file.remove(deleted.subtracting(pending))
            if file.captures.count != countBefore { changed = true }
        }
        AttachmentStore.remove(for: deleted.subtracting(pending))
        return changed
    }

    /// The most recent earlier capture of the same link, if there is one.
    static func previous(matching url: URL, excluding id: Capture.ID? = nil) -> Capture? {
        let key = Capture.matchKey(for: url)
        return load().first { $0.id != id && $0.matchKey == key }
    }

    // MARK: - File access

    private static func update(_ change: (inout HistoryFile) -> Void) {
        coordinate(writing: true) { url in
            guard var file = read(url) ?? setAside(url) else { return }
            change(&file)
            file.captures.sort { $0.date > $1.date }
            guard let data = try? file.encoded() else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The file's contents: empty if there's no file yet, nil if it's there but isn't a history at all.
    private static func read(_ url: URL) -> HistoryFile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return HistoryFile() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? HistoryFile(data: data)
    }

    /// Moves a damaged file aside, rather than writing over it, so a fresh history can start
    /// without losing what was there. Returns nil, so nothing is written, if it can't be moved.
    private static func setAside(_ url: URL) -> HistoryFile? {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("captures-damaged-\(Int(Date.now.timeIntervalSince1970)).json")
        guard (try? FileManager.default.moveItem(at: url, to: backup)) != nil else { return nil }
        return HistoryFile()
    }

    private static func coordinate(writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: .forMerging, error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &error, byAccessor: body)
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// What's in the history file. Each entry is read on its own, so one this version can't read
/// (saved by a newer version of Campfire, say) doesn't take the others with it. Such entries are
/// kept exactly as they are and written back, so they aren't lost either. Likewise, fields a newer
/// version added to an entry this version can read are carried over when it's written back.
struct HistoryFile {
    var captures: [Capture] = []
    var unreadable: [[String: Any]] = []
    /// Fields this version doesn't know about, by entry.
    private var unknownFields: [Capture.ID: [String: Any]] = [:]

    init() {}

    /// Fails only if the data isn't a list at all.
    init(data: Data) throws {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for case let entry as [String: Any] in entries {
            if let entryData = try? JSONSerialization.data(withJSONObject: entry),
               let capture = try? CaptureStore.decoder.decode(Capture.self, from: entryData) {
                captures.append(capture)
                let unknown = entry.filter { !Self.knownFields.contains($0.key) }
                if !unknown.isEmpty { unknownFields[capture.id] = unknown }
            } else {
                unreadable.append(entry)
            }
        }
    }

    func encoded() throws -> Data {
        let readable = try captures.map { capture in
            var entry = try JSONSerialization.jsonObject(with: CaptureStore.encoder.encode(capture)) as? [String: Any] ?? [:]
            entry.merge(unknownFields[capture.id] ?? [:]) { known, _ in known }
            return entry
        }
        return try JSONSerialization.data(withJSONObject: readable + unreadable)
    }

    /// Every field this version saves, found by saving an entry with all of them filled in.
    private static let knownFields: Set<String> = {
        let full = Capture(title: "", url: URL(string: "https://example.com"), summary: "", note: "", text: "",
                           destination: .notion, status: .failed, errorMessage: "")
        let entry = (try? CaptureStore.encoder.encode(full))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return Set(entry.keys)
    }()

    mutating func remove(_ ids: Set<Capture.ID>) {
        captures.removeAll { ids.contains($0.id) }
        unreadable.removeAll { Self.id(of: $0).map(ids.contains) ?? false }
    }

    static func id(of entry: [String: Any]) -> Capture.ID? {
        (entry["id"] as? String).flatMap(UUID.init(uuidString:))
    }
}
