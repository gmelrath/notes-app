import Foundation
import LinkPresentation

/// Title and description for a web page, read from its HTML `<meta>` tags.
struct LinkMetadata {
    var title: String?
    var description: String?

    /// Reads the page itself, then, if that gives no title (the site blocked the request, or sets
    /// its title only once the page has loaded), asks Apple's link-preview service, which Messages uses.
    static func fetch(for url: URL) async -> LinkMetadata {
        var metadata = await fetchPage(url)
        if metadata.title == nil { metadata.title = await previewTitle(for: url) }
        return metadata
    }

    private static func fetchPage(_ url: URL) async -> LinkMetadata {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        // A blocked request still returns a page, such as a "Just a moment..." check; ignore it.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            return LinkMetadata()
        }
        // The <head> is near the top; no need to scan a huge page.
        let html = String(decoding: data.prefix(600_000), as: UTF8.self)
        return parse(html: html)
    }

    static func parse(html: String) -> LinkMetadata {
        var meta: [String: String] = [:]
        for tag in matches(of: #"<meta\b[^>]*>"#, in: html) {
            let attributes = attributes(in: tag)
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"], !content.isEmpty else { continue }
            if meta[key] == nil { meta[key] = content }
        }

        let titleTag = firstCapture(of: #"<title[^>]*>([\s\S]*?)</title>"#, in: html)
        let title = meta["og:title"] ?? meta["twitter:title"] ?? titleTag
        let description = meta["og:description"] ?? meta["twitter:description"] ?? meta["description"]

        // Posts arrive with their paragraphs in the description; keep the line breaks.
        return LinkMetadata(title: title.map { clean($0) }, description: description.map { clean($0, keepingLineBreaks: true) })
    }

    @MainActor
    private static func previewTitle(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let title = (try? await provider.startFetchingMetadata(for: url))?.title else { return nil }
        let cleaned = TitleText.flattened(title)
        // The service falls back to the bare address, which is no better than ours.
        return cleaned.isEmpty || cleaned == url.host() || cleaned == url.absoluteString ? nil : cleaned
    }

    /// A readable title from the link itself, for when the page gives none:
    /// ".../how-i-use-claude-as-a-product-manager-edc23b7d8123" → "How I Use Claude As A Product Manager".
    /// Nil when the address has no words to use, as with short links like "lnkd.in/p/ef6c2Pr3".
    static func title(fromAddress url: URL) -> String? {
        let segment = url.pathComponents.reversed().first { component in
            component != "/" && component.contains { $0 == "-" || $0 == "_" }
        }
        guard let segment else { return nil }
        var words = (segment as NSString).deletingPathExtension
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "+" })
            .map(String.init)
        // Sites add an ID to the end: "...-edc23b7d8123", "...-7524543751785095169".
        while let last = words.last, words.count > 1, last.count >= 6,
              last.allSatisfy(\.isHexDigit) && last.contains(where: \.isNumber) {
            words.removeLast()
        }
        guard words.count >= 2, words.contains(where: { $0.contains(where: \.isLetter) }) else { return nil }
        let title = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return TitleText.shortened(title)
    }

    // MARK: - Helpers

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func firstCapture(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueRange = Range(match.range(at: 2), in: tag) ?? Range(match.range(at: 3), in: tag)
            result[tag[nameRange].lowercased()] = valueRange.map { String(tag[$0]) } ?? ""
        }
        return result
    }

    /// Decodes common HTML entities and collapses whitespace, optionally keeping line breaks
    /// (at most one blank line in a row).
    private static func clean(_ raw: String, keepingLineBreaks: Bool = false) -> String {
        var text = raw
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, value) in named { text = text.replacingOccurrences(of: entity, with: value) }

        if let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let whole = Range(match.range, in: text),
                      let hexFlag = Range(match.range(at: 1), in: text),
                      let digits = Range(match.range(at: 2), in: text),
                      let code = UInt32(text[digits], radix: text[hexFlag].isEmpty ? 10 : 16),
                      let scalar = Unicode.Scalar(code) else { continue }
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }

        guard keepingLineBreaks else { return TitleText.flattened(text) }
        return text
            .components(separatedBy: .newlines)
            .map(TitleText.flattened)
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What a link fills in on the compose screen and the share card.
struct LinkDetails {
    var title: String?
    var summary: String?
    var isPost = false
}

extension LinkMetadata {
    /// Reads `url` and decides what it fills in. The title is the page's own (shortened for a post),
    /// else the one the sharing app sent, else one made from the address.
    static func details(for url: URL, sharedTitle: String? = nil) async -> LinkDetails {
        let metadata = await fetch(for: url)
        let title = [metadata.suggestedTitle, sharedTitle, title(fromAddress: url)]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        return LinkDetails(title: title, summary: metadata.description, isPost: metadata.isPost)
    }

    /// A web link typed or pasted on its own, with or without "https://", or the first web link
    /// inside longer text. Other kinds of link, like email addresses and phone numbers, don't count.
    static func webLink(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
            .lazy
            .compactMap(\.url)
            .first { $0.scheme == "http" || $0.scheme == "https" }
    }

    /// Whether the link is a social post (LinkedIn, X, Threads and the like) rather than an article.
    /// Posts have no real title: their "title" is the post's opening, cut short, and the description
    /// is the post itself. A real headline, like a Medium article's, isn't the start of its description.
    var isPost: Bool {
        guard let description else { return false }
        let post = TitleText.flattened(description)
        // Article descriptions are a sentence or two; only a post runs this long.
        if post.count >= 800 { return true }
        guard let title else { return false }
        // "Opening of the post… | Author | 24 comments" → "Opening of the post"
        let opening = TitleText.flattened(String(title.prefix { $0 != "…" }).components(separatedBy: " | ")[0])
        return opening.count >= 20 && post.hasPrefix(opening)
    }

    /// The title to fill in: a post's opening, shortened, or the page's own title, shortened only
    /// when it's far longer than any real headline.
    var suggestedTitle: String? {
        if isPost, let description { return TitleText.shortened(TitleText.flattened(description)) }
        guard let title else { return nil }
        return title.count > 150 ? TitleText.shortened(title) : title
    }
}

enum TitleText {
    /// The length a shortened title or preview is cut to, "…" included.
    static let titleLength = 65

    /// `text` cut at the end of a word to fit `limit` characters, ending in "…", or as it is if it fits.
    static func shortened(_ text: String, limit: Int = titleLength) -> String {
        guard text.count > limit else { return text }
        var cut = String(text.prefix(limit - 1))
        if let space = cut.lastIndex(where: \.isWhitespace), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",;:-–—"))) + "…"
    }

    /// All runs of spaces and line breaks turned into single spaces.
    static func flattened(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
