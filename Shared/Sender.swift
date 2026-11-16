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
    private static func folder(for id: Capture.ID) -> URL {
        AppGroup.folder
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func save(_ files: [URL], for id: Capture.ID) {
        let directory = folder(for: id)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            try? FileManager.default.copyItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
        }
    }

    static func files(for id: Capture.ID) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder(for: id), includingPropertiesForKeys: nil)) ?? []
    }

    static func remove(for ids: some Sequence<Capture.ID>) {
        for id in ids {
            try? FileManager.default.removeItem(at: folder(for: id))
        }
    }
}
