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
    }

    static func delete(ids: Set<Capture.ID>) {
        update { captures in captures.removeAll { ids.contains($0.id) } }
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

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
