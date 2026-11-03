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
        coordinate(writing: false) { url in result = read(url) }
        return result
    }

    static func save(_ capture: Capture) {
        update { captures in
            captures.removeAll { $0.id == capture.id }
            captures.insert(capture, at: 0)
        }
        CloudQueue.markSaved([capture.id])
    }

    static func delete(ids: Set<Capture.ID>) {
        update { captures in captures.removeAll { ids.contains($0.id) } }
        CloudQueue.markDeleted(ids)
    }

    /// Applies changes from other devices. Entries with local changes still waiting to upload are
    /// left alone, so they aren't overwritten by an older copy. Returns whether anything changed.
    static func merge(saved: [Capture], deleted: Set<Capture.ID>, keeping pending: Set<Capture.ID>) -> Bool {
        guard !saved.isEmpty || !deleted.isEmpty else { return false }
        var changed = false
        update { captures in
            for capture in saved where !pending.contains(capture.id) {
                if let index = captures.firstIndex(where: { $0.id == capture.id }) {
                    if captures[index] != capture {
                        captures[index] = capture
                        changed = true
                    }
                } else {
                    captures.append(capture)
                    changed = true
                }
            }
            let countBefore = captures.count
            captures.removeAll { deleted.contains($0.id) && !pending.contains($0.id) }
            if captures.count != countBefore { changed = true }
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

    private static func update(_ change: (inout [Capture]) -> Void) {
        coordinate(writing: true) { url in
            var captures = read(url)
            change(&captures)
            captures.sort { $0.date > $1.date }
            guard let data = try? encoder.encode(captures) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func read(_ url: URL) -> [Capture] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([Capture].self, from: data)) ?? []
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
