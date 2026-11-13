import Foundation
import Testing
@testable import Campfire

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
    ])
    func sameKey(_ first: String, _ second: String) throws {
        #expect(try key(first) == key(second))
    }

    @Test("Different pages stay different", arguments: [
        ("https://example.com/post-1", "https://example.com/post-2"),
        ("https://example.com/post?id=1", "https://example.com/post?id=2"),
        ("https://example.com/post", "https://example.org/post"),
    ])
    func differentKey(_ first: String, _ second: String) throws {
        #expect(try key(first) != key(second))
    }

    @Test func entryUsesItsLink() {
        let capture = Capture(title: "x", url: URL(string: "https://www.example.com/post?utm_source=a"), destination: .notion, status: .sent)
        #expect(capture.matchKey == "example.com/post")
        #expect(Capture(title: "Note", destination: .email, status: .sent).matchKey == nil)
    }
}
