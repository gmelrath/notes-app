import Foundation

enum SendError: LocalizedError {
    case notConnected(Destination)
    case noEmailAddress

    var errorDescription: String? {
        switch self {
        case .notConnected(let destination): "\(destination.rawValue) isn't connected yet."
        case .noEmailAddress: "Add an email address in Settings."
        }
    }
}

/// Delivers a capture to Notion or email. Email is a placeholder until phase 4.
enum Sender {
    static func send(_ capture: Capture, to destination: Destination) async throws {
        switch destination {
        case .notion:
            try await NotionClient.addPage(for: capture)
        case .email:
            guard AppSettings.emailAddress != nil else { throw SendError.noEmailAddress }
            throw SendError.notConnected(.email)
        }
    }
}
