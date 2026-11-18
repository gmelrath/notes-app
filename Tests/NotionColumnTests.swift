import Foundation
import Testing
@testable import Campfire

@Suite("Picking Notion columns")
struct NotionColumnPickTests {
    private func column(_ id: String, _ name: String, _ type: String) -> [String: Any] {
        ["id": id, "name": name, "type": type]
    }

    /// "Things to Read…" as it is today.
    private var today: [String: Any] {
        ["Title": column("title", "Title", "title"),
         "URL": column("u%3Ab1", "URL", "url"),
         "Summary": column("s%7Bx2", "Summary", "rich_text"),
         "Tags": column("t%40c3", "Tags", "multi_select")]
    }

    @Test func todaysColumns() {
        #expect(NotionColumns.pick(from: today) == NotionColumns(title: "title", url: "u%3Ab1", summary: "s%7Bx2"))
    }

    @Test func renamedColumnsAreStillFound() {
        let renamed: [String: Any] = [
            "Name": column("title", "Name", "title"),
            "Link": column("u%3Ab1", "Link", "url"),
            "Notes": column("s%7Bx2", "Notes", "rich_text"),
        ]
        #expect(NotionColumns.pick(from: renamed) == NotionColumns(title: "title", url: "u%3Ab1", summary: "s%7Bx2"))
    }

    @Test func withTwoTextColumnsTheOneNamedSummaryWins() {
        var columns = today
        columns["Author"] = column("a%3Dd4", "Author", "rich_text")
        #expect(NotionColumns.pick(from: columns)?.summary == "s%7Bx2")
    }

    @Test func withTwoTextColumnsAndNoSummaryNeitherIsGuessed() {
        var columns = today
        columns["Summary"] = nil
        columns["Author"] = column("a%3Dd4", "Author", "rich_text")
        columns["Source"] = column("o%3De5", "Source", "rich_text")
        #expect(NotionColumns.pick(from: columns)?.summary == nil)
    }

    @Test func missingColumnsAreLeftOut() {
        let titleOnly: [String: Any] = ["Title": column("title", "Title", "title")]
        #expect(NotionColumns.pick(from: titleOnly) == NotionColumns(title: "title", url: nil, summary: nil))
    }

    @Test func noTitleColumnIsNotADatabase() {
        #expect(NotionColumns.pick(from: ["URL": column("u", "URL", "url")]) == nil)
    }
}

@Suite("Notion pages by column")
struct NotionPageBodyTests {
    private let all = NotionColumns(title: "title", url: "u1", summary: "s1")

    private func properties(_ body: [String: Any]) -> [String: Any] { body["properties"] as? [String: Any] ?? [:] }
    private func blocks(_ body: [String: Any]) -> [[String: Any]] { body["children"] as? [[String: Any]] ?? [] }
    private func text(of block: [String: Any]) -> String {
        let rich = (block["paragraph"] as? [String: Any])?["rich_text"] as? [[String: Any]] ?? []
        return rich.compactMap { ($0["text"] as? [String: Any])?["content"] as? String }.joined()
    }

    private let article = Capture(title: "Interface Patterns", url: URL(string: "https://example.com/a"),
                                  summary: "A library of patterns.", destination: .notion, status: .sent)

    @Test func sendsByColumnID() {
        let body = NotionClient.pageBody(for: article, columns: all, dataSourceID: "db")
        #expect(Set(properties(body).keys) == ["title", "u1", "s1"])
        #expect(blocks(body).isEmpty)
        #expect((body["parent"] as? [String: String])?["data_source_id"] == "db")
    }

    @Test func noSummaryColumnPutsTheDescriptionInThePage() {
        let body = NotionClient.pageBody(for: article, columns: NotionColumns(title: "title", url: "u1"), dataSourceID: "db")
        #expect(Set(properties(body).keys) == ["title", "u1"])
        #expect(blocks(body).map(text(of:)) == ["A library of patterns."])
    }

    @Test func noURLColumnPutsTheLinkAtTheTopOfThePage() {
        let body = NotionClient.pageBody(for: article, columns: NotionColumns(title: "title", summary: "s1"), dataSourceID: "db")
        #expect(Set(properties(body).keys) == ["title", "s1"])
        #expect(blocks(body).first.map(text(of:)) == "https://example.com/a")
    }

    @Test func postsKeepTheirFullTextWithoutASummaryColumn() {
        var post = Capture(title: "Short title…", url: URL(string: "https://lnkd.in/p/x"), summary: "Line one\nLine two", destination: .notion, status: .sent)
        post.isPost = true
        let body = NotionClient.pageBody(for: post, columns: NotionColumns(title: "title", url: "u1"), dataSourceID: "db")
        #expect(blocks(body).map(text(of:)) == ["Line one", "Line two"])
    }

    @Test func recognisesAColumnProblem() {
        #expect(NotionClient.isColumnProblem(ServiceResponse(status: 400, message: "Summary is not a property that exists.")))
        #expect(!NotionClient.isColumnProblem(ServiceResponse(status: 400, message: "body failed validation: title too long")))
        #expect(!NotionClient.isColumnProblem(ServiceResponse(status: 401, message: "Unauthorized property access")))
    }
}
