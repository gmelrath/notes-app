import Foundation

/// Where a capture can be sent. Each destination answers the same questions below, so the screens
/// and the history ask it rather than checking for Notion or Email by name.
///
/// To add a destination: add a case here and answer each question (the compiler lists every place),
/// give it a keyboard shortcut in SendButtonRow.swift, send it in Sender.swift, and add any key it
/// needs to Secrets and Settings.
enum Destination: String, Codable, CaseIterable {
    case notion = "Notion"
    case email = "Email"
}

extension Destination {
    var systemImage: String {
        switch self {
        case .notion: "books.vertical"
        case .email: "envelope"
        }
    }

    /// Whether it can take what's being sent: a link, some text (a note or shared text), files.
    func accepts(hasLink: Bool, hasText: Bool, hasFiles: Bool) -> Bool {
        switch self {
        // A Notion entry is a link or some words; files alone have nowhere to go.
        case .notion: hasLink || hasText
        case .email: hasLink || hasText || hasFiles
        }
    }

    /// Whether shared files go along, as attachments.
    var sendsFiles: Bool {
        switch self {
        case .notion: false
        case .email: true
        }
    }

    /// Whether the note typed on the share card goes along. Notion's entry is the shared page or
    /// text itself, so the card's note is only for email.
    var includesShareCardNote: Bool {
        switch self {
        case .notion: false
        case .email: true
        }
    }

    /// Whether everything it needs from Settings is in place.
    var isSetUp: Bool {
        switch self {
        // The Notion key is checked when sending, with its own message.
        case .notion: true
        case .email: AppSettings.emailAddress != nil
        }
    }

    /// What to do before it can send, when it isn't set up. `settings` names where Settings is,
    /// which differs between the app and the share card.
    func setupHint(settings: String) -> String? {
        guard !isSetUp else { return nil }
        switch self {
        case .notion: return nil
        case .email: return "To send by email, add your address in \(settings)."
        }
    }

    /// Whether retrying a failed send of `capture` is possible: a destination that sends files
    /// needs the copies kept on this device.
    func canRetry(_ capture: Capture) -> Bool {
        !sendsFiles || capture.fileNames.isEmpty || !AttachmentStore.files(for: capture.id).isEmpty
    }
}
