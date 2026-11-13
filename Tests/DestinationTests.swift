import Foundation
import SwiftUI
import Testing
@testable import Campfire

@Suite("Destination rules")
struct DestinationTests {
    @Test func notionTakesLinksAndText() {
        #expect(Destination.notion.accepts(hasLink: true, hasText: false, hasFiles: false))
        #expect(Destination.notion.accepts(hasLink: false, hasText: true, hasFiles: false))
        #expect(!Destination.notion.accepts(hasLink: false, hasText: false, hasFiles: true))
        #expect(!Destination.notion.accepts(hasLink: false, hasText: false, hasFiles: false))
    }

    @Test func emailTakesAnything() {
        #expect(Destination.email.accepts(hasLink: false, hasText: false, hasFiles: true))
        #expect(Destination.email.accepts(hasLink: true, hasText: false, hasFiles: false))
        #expect(Destination.email.accepts(hasLink: false, hasText: true, hasFiles: false))
        #expect(!Destination.email.accepts(hasLink: false, hasText: false, hasFiles: false))
    }

    @Test func onlyEmailSendsFilesAndTheShareCardNote() {
        #expect(Destination.email.sendsFiles && !Destination.notion.sendsFiles)
        #expect(Destination.email.includesShareCardNote && !Destination.notion.includesShareCardNote)
    }

    @Test func notionNeedsNoSetupHint() {
        #expect(Destination.notion.isSetUp)
        #expect(Destination.notion.setupHint(settings: "Settings") == nil)
    }

    @Test func everyDestinationHasAnIconAndShortcut() {
        for destination in Destination.allCases {
            #expect(!destination.systemImage.isEmpty)
            #expect(!destination.shortcutModifiers.isEmpty)
        }
        #expect(Set(Destination.allCases.map(\.shortcutModifiers.rawValue)).count == Destination.allCases.count)
    }

    @Test func retryRules() {
        #expect(Destination.notion.canRetry(Capture(title: "x", fileNames: ["a.pdf"], destination: .notion, status: .failed)))
        #expect(Destination.email.canRetry(Capture(title: "x", destination: .email, status: .failed)))
        // An email with files needs the copies kept on this device; a fresh entry has none.
        #expect(!Destination.email.canRetry(Capture(title: "x", fileNames: ["a.pdf"], destination: .email, status: .failed)))
    }
}

@Suite("Notes")
struct NoteTests {
    @Test("The title is the first line", arguments: [
        ("Call the dentist\nAsk about Thursday", "Call the dentist"),
        ("Buy milk", "Buy milk"),
        ("\n\n  Spaced out  \nsecond", "Spaced out"),
        ("", ""),
    ])
    func title(note: String, title: String) {
        #expect(Capture.title(forNote: note) == title)
    }
}
