import Foundation
import Testing
@testable import Campfire

@Suite("Finding links")
struct WebLinkTests {
    @Test("Finds web links", arguments: [
        ("https://example.com/a", "example.com"),
        ("example.com/article", "example.com"),
        ("Read this: https://medium.com/x/post-1 tonight", "medium.com"),
        ("Contact sam@example.com — read https://medium.com/x/post-1 first", "medium.com"),
    ])
    func findsWebLinks(text: String, host: String) {
        #expect(LinkMetadata.webLink(in: text)?.host() == host)
    }

    @Test("Ignores what isn't a web link", arguments: [
        "Email sam@example.com or call 555-123-4567",
        "mailto:sam@example.com",
        "tel:5551234567",
        "   ",
        "",
    ])
    func ignoresOtherLinks(text: String) {
        #expect(LinkMetadata.webLink(in: text) == nil)
    }
}

@Suite("Reading pages")
struct PageTests {
    @Test func readsTitleAndDescription() {
        let page = LinkMetadata.parse(html: SamplePages.article)
        #expect(page.title == "Interface Patterns | Sam Rivera")
        #expect(page.description == "A library of patterns for inventing new interfaces.")
    }

    @Test func decodesEntitiesAndTidiesSpaces() {
        #expect(LinkMetadata.parse(html: SamplePages.medium).title == "I Rebuilt Our Onboarding in 30 Days: Here's What Actually Moved Retention")
        #expect(LinkMetadata.parse(html: SamplePages.titleTagOnly).title == "Plain Page Title")
    }

    @Test func keepsLineBreaksInPosts() {
        let post = LinkMetadata.parse(html: SamplePages.post).description ?? ""
        #expect(post.contains("five customer calls.\n\nWhat changed:\n\n- Fewer features & better ones"))
    }
}

@Suite("Link titles")
struct LinkTitleTests {
    @Test func recognisesPosts() {
        #expect(LinkMetadata.parse(html: SamplePages.post).isPost)
        #expect(LinkMetadata.parse(html: SamplePages.hashtagPost).isPost)
        #expect(!LinkMetadata.parse(html: SamplePages.article).isPost)
        #expect(!LinkMetadata.parse(html: SamplePages.medium).isPost)
    }

    @Test func postTitleIsTheShortenedOpening() throws {
        let title = try #require(LinkMetadata.parse(html: SamplePages.post).suggestedTitle)
        #expect(title == "Most teams ship features nobody asked for. Here is how we…")
        #expect(title.count <= TitleText.titleLength)
    }

    @Test func hashtagPostTitleComesFromTheText() throws {
        let title = try #require(LinkMetadata.parse(html: SamplePages.hashtagPost).suggestedTitle)
        #expect(title.hasPrefix("AI makes it much easier to build software."))
        #expect(!title.contains("#"))
    }

    @Test func realHeadlinesAreKeptWhole() {
        let medium = LinkMetadata.parse(html: SamplePages.medium)
        #expect(medium.suggestedTitle == medium.title)
        #expect((medium.title ?? "").count > TitleText.titleLength)
    }

    @Test func veryLongTitlesAreShortened() {
        let page = LinkMetadata(title: String(repeating: "word ", count: 40), description: "Short subtitle.")
        #expect((page.suggestedTitle ?? "").count <= TitleText.titleLength)
    }

    @Test("Titles from the web address", arguments: [
        ("https://medium.com/pub/how-i-use-claude-as-a-product-manager-edc23b7d8123", "How I Use Claude As A Product Manager"),
        ("https://blog.example.com/2026/11/a-decade-of-design.html", "A Decade Of Design"),
        ("https://example.com/posts/launch_notes_2026", "Launch Notes 2026"),
    ])
    func addressTitles(link: String, title: String) throws {
        #expect(LinkMetadata.title(fromAddress: try #require(URL(string: link))) == title)
    }

    @Test("No address title without words", arguments: [
        "https://lnkd.in/p/ef6c2Pr3",
        "https://example.com/",
        "https://example.com/about",
    ])
    func noAddressTitle(link: String) throws {
        #expect(LinkMetadata.title(fromAddress: try #require(URL(string: link))) == nil)
    }
}

@Suite("Shortening text")
struct TitleTextTests {
    @Test func shortTextIsUnchanged() {
        #expect(TitleText.shortened("A short title") == "A short title")
    }

    @Test func cutsAtAWordAndAddsAnEllipsis() {
        let text = "This sentence is deliberately long so that it has to be cut somewhere sensible"
        let short = TitleText.shortened(text, limit: 30)
        #expect(short == "This sentence is…")
        #expect(short.count <= 30)
    }

    @Test func dropsTrailingPunctuationBeforeTheEllipsis() {
        #expect(TitleText.shortened("Alpha beta, gamma delta", limit: 14) == "Alpha beta…")
    }

    @Test func flattensSpacesAndLineBreaks() {
        #expect(TitleText.flattened("  one\n\n two\tthree ") == "one two three")
    }
}
