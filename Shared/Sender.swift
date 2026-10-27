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

/// Delivers a capture to Notion or email. Both are placeholders until phases 3 and 4.
enum Sender {
    static func send(_ capture: Capture, to destination: Destination) async throws {
        switch destination {
        case .notion:
            throw SendError.notConnected(.notion)
        case .email:
            guard AppSettings.emailAddress != nil else { throw SendError.noEmailAddress }
            throw SendError.notConnected(.email)
        }
    }
}
