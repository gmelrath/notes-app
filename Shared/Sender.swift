import Foundation

enum SendError: LocalizedError {
    case noEmailAddress

    var errorDescription: String? {
        switch self {
        case .noEmailAddress: "Add an email address in Settings."
        }
    }
}

/// Delivers a capture to Notion or email.
enum Sender {
    /// `attachments` are the shared files' local copies; only email sends them.
    static func send(_ capture: Capture, to destination: Destination, attachments: [URL] = []) async throws {
        switch destination {
        case .notion:
            try await NotionClient.addPage(for: capture)
        case .email:
            guard let address = AppSettings.emailAddress else { throw SendError.noEmailAddress }
            try await EmailClient.send(capture, to: address, attachments: attachments)
        }
    }
}

/// Copies of shared files kept in the App Group after a failed email, so it can be retried from History.
enum AttachmentStore {
    private static func folder(for id: Capture.ID) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func save(_ files: [URL], for id: Capture.ID) {
        guard let folder = folder(for: id) else { return }
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try? FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
        }
    }

    static func files(for id: Capture.ID) -> [URL] {
        guard let folder = folder(for: id) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    static func remove(for ids: some Sequence<Capture.ID>) {
        for id in ids {
            if let folder = folder(for: id) { try? FileManager.default.removeItem(at: folder) }
        }
    }
}
