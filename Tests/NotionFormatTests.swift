import Foundation
import Testing
@testable import Campfire

@Suite("Notion text limits")
struct NotionLimitTests {
    private func pieces(_ rich: [[String: Any]]) -> [String] {
        rich.compactMap { ($0["text"] as? [String: String])?["content"] }
    }

    @Test("Fits Notion's count, never splitting a character", arguments: [
        "👉 " + String(repeating: "a", count: 2100),          // the NMB-17 bug: one emoji counts twice
        String(repeating: "Great post 🚀🔥 ", count: 200),
        String(repeating: "a", count: 1998) + "👍👍👍",
        String(repeating: "👨‍👩‍👧‍👦", count: 300),
        String(repeating: "café ", count: 500),
    ])
    func fitted(text: String) {
        let out = NotionClient.fitted(text, limit: 2000)
        #expect(out.utf16.count <= 2000)
        #expect(out.hasSuffix("…"))
        #expect(text.hasPrefix(String(out.dropLast())))
    }

    @Test func textWithinTheLimitIsUnchanged() {
        let exact = String(repeating: "b", count: 2000)
        #expect(NotionClient.fitted(exact, limit: 2000) == exact)
        #expect(NotionClient.fitted("Short 🎉", limit: 2000) == "Short 🎉")
    }

    @Test func longTextIsSplitNotCut() {
        let long = String(repeating: "Great post 🚀 ", count: 400)
        let parts = pieces(NotionClient.richText(long))
        #expect(parts.count > 1)
        #expect(parts.joined() == long)
        #expect(parts.allSatisfy { $0.utf16.count <= 2000 })
    }

    @Test func emptyTextIsOnePiece() {
        #expect(pieces(NotionClient.richText("")) == [""])
    }

    @Test func pageBodyIsOneParagraphPerLine() {
        let blocks = NotionClient.paragraphs("First line\n\n  Second line  \nThird")
        #expect(blocks.count == 3)
        let texts = blocks.compactMap { (($0["paragraph"] as? [String: Any])?["rich_text"] as? [[String: Any]]).map(pieces)?.joined() }
        #expect(texts == ["First line", "Second line", "Third"])
    }

    @Test func pageBodyStaysWithinNotionsBlockLimit() {
        let lines = (1...150).map { "Line \($0)" }.joined(separator: "\n")
        let blocks = NotionClient.paragraphs(lines)
        #expect(blocks.count == 100)
    }
}

@Suite("What goes where in Notion")
struct NotionLayoutTests {
    @Test func postGoesInThePageBodyWithAPreview() throws {
        let page = LinkMetadata.parse(html: SamplePages.post)
        var post = Capture(title: try #require(page.suggestedTitle), url: URL(string: "https://lnkd.in/p/x"),
                           summary: page.description, destination: .notion, status: .sent)
        post.isPost = true
        #expect(NotionClient.pageText(for: post) == page.description)
        #expect((NotionClient.summary(for: post) ?? "").count <= NotionClient.previewLength)
    }

    @Test func noteGoesInThePageBody() {
        let note = Capture(title: "Call the dentist", note: "Call the dentist\nAsk about Thursday\nBring card", destination: .notion, status: .sent)
        #expect(NotionClient.pageText(for: note) == note.note)
        #expect(NotionClient.summary(for: note) == "Ask about Thursday Bring card")
    }

    @Test func oneLineNoteHasNoSummary() {
        let note = Capture(title: "Buy milk", note: "Buy milk", destination: .notion, status: .sent)
        #expect(NotionClient.summary(for: note) == "")
        #expect(NotionClient.pageText(for: note) == "Buy milk")
    }

    @Test func olderNoteEntriesStillGetTheWholeNote() {
        // Saved before NMB-20: the note held only the lines after the title.
        let old = Capture(title: "Call the dentist", note: "Ask about Thursday", destination: .notion, status: .failed)
        #expect(NotionClient.pageText(for: old) == "Call the dentist\nAsk about Thursday")
        #expect(NotionClient.summary(for: old) == "Ask about Thursday")
    }

    @Test func sharedTextWithoutALinkActsAsANote() {
        let shared = Capture(title: "Highlight from a book", text: "Highlight from a book\nThe rest of the passage.", destination: .notion, status: .sent)
        #expect(NotionClient.pageText(for: shared) == shared.text)
        #expect(NotionClient.summary(for: shared) == "The rest of the passage.")
    }

    @Test func articleIsUnchanged() {
        let article = Capture(title: "Interface Patterns", url: URL(string: "https://example.com/a"), summary: "A library.", destination: .notion, status: .sent)
        #expect(NotionClient.pageText(for: article) == nil)
        #expect(NotionClient.summary(for: article) == "A library.")
    }

    @Test func noteBeatsTheDescriptionForLinks() {
        let link = Capture(title: "Article", url: URL(string: "https://example.com/a"), summary: "Desc", note: "My take", destination: .notion, status: .sent)
        #expect(NotionClient.summary(for: link) == "My take")
        #expect(NotionClient.pageText(for: link) == nil)
    }
}
