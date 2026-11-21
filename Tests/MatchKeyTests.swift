import Foundation
import Testing
@testable import Stowaway

/// The duplicate warning compares links by their match key, so these must agree for the same page.
@Suite("Duplicate matching")
struct MatchKeyTests {
    private func key(_ link: String) throws -> String {
        Capture.matchKey(for: try #require(URL(string: link)))
    }

    @Test("Same page, different trimmings", arguments: [
        ("https://www.example.com/post", "https://example.com/post"),
        ("https://m.example.com/post", "https://example.com/post"),
        ("https://EXAMPLE.com/post", "https://example.com/post"),
        ("https://example.com/post/", "https://example.com/post"),
        ("https://example.com/post#comments", "https://example.com/post"),
        ("https://twitter.com/sam/status/1", "https://x.com/sam/status/1"),
        ("https://example.com/post?utm_source=share&utm_medium=ios", "https://example.com/post"),
        ("https://example.com/post?fbclid=abc&gclid=def", "https://example.com/post"),
        ("https://x.com/sam/status/1?s=20&t=abc", "https://x.com/sam/status/1"),
        ("https://example.com/post?b=2&a=1", "https://example.com/post?a=1&b=2"),
        ("https://example.com/post?trk=feed&lipi=abc", "https://example.com/post"),
        ("https://example.com/post?smid=url-share&_hsenc=x&_hsmi=y&mkt_tok=z", "https://example.com/post"),
        ("https://www.youtube.com/watch?v=abc123&feature=share", "https://youtube.com/watch?v=abc123"),
        ("https://example.com/post?share=1&igsh=abc", "https://example.com/post"),
    ])
    func sameKey(_ first: String, _ second: String) throws {
        #expect(try key(first) == key(second))
    }

    @Test("Different pages stay different", arguments: [
        ("https://example.com/post-1", "https://example.com/post-2"),
        ("https://example.com/post?id=1", "https://example.com/post?id=2"),
        ("https://example.com/post", "https://example.org/post"),
        ("https://www.youtube.com/watch?v=abc123", "https://www.youtube.com/watch?v=def456"),
        ("https://medium.com/@stezz/one-article-0583853c5074", "https://medium.com/@stezz/another-article-1b552472ed9f"),
        ("https://medium.com/@stezz", "https://medium.com/@other"),
    ])
    func differentKey(_ first: String, _ second: String) throws {
        #expect(try key(first) != key(second))
    }

    @Test("A Medium article matches under any of its addresses", arguments: [
        "https://stezz.medium.com/ai-is-turning-product-managers-into-architects-nobody-asked-them-0583853c5074",
        "https://medium.com/@stezz/ai-is-turning-product-managers-into-architects-nobody-asked-them-0583853c5074",
        "https://medium.com/agileinsider/ai-is-turning-product-managers-into-architects-nobody-asked-them-0583853c5074?source=rss",
        "https://medium.com/p/0583853c5074",
    ])
    func mediumArticle(link: String) throws {
        #expect(try key(link) == "medium.com/p/0583853c5074")
    }

    @Test func mediumProfilesAreOrdinaryLinks() throws {
        #expect(try key("https://medium.com/@stezz") == "medium.com/@stezz")
    }

    @Test func aShortLinkMatchesTheBrowserLinkThroughTheOfficialAddress() throws {
        // Shared from the LinkedIn app: a short link, whose page names its official address.
        let fromApp = Capture(title: "Post", url: URL(string: "https://lnkd.in/p/ef6c2Pr3"),
                              canonicalURL: URL(string: "https://www.linkedin.com/posts/sam_post-activity-7524543753077084160-UX_J"),
                              destination: .notion, status: .sent)
        // Shared later from a browser: the official address, with tracking codes.
        let fromBrowser = [try #require(URL(string: "https://www.linkedin.com/posts/sam_post-activity-7524543753077084160-UX_J?utm_source=share&utm_medium=member_desktop&rcm=abc"))]
        #expect(!fromApp.matchKeys.isDisjoint(with: fromBrowser.map(Capture.matchKey(for:))))

        let unrelated = Capture(title: "Other", url: URL(string: "https://lnkd.in/p/zzzzzzzz"), destination: .notion, status: .sent)
        #expect(unrelated.matchKeys.isDisjoint(with: fromBrowser.map(Capture.matchKey(for:))))
    }

    @Test func entryUsesItsLink() {
        let capture = Capture(title: "x", url: URL(string: "https://www.example.com/post?utm_source=a"), destination: .notion, status: .sent)
        #expect(capture.matchKey == "example.com/post")
        #expect(Capture(title: "Note", destination: .email, status: .sent).matchKey == nil)
    }
}
