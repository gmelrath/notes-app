import Foundation

/// Title and description for a web page, read from its HTML `<meta>` tags.
struct LinkMetadata {
    var title: String?
    var description: String?

    static func fetch(for url: URL) async -> LinkMetadata {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
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

        return LinkMetadata(title: title.map(clean), description: description.map(clean))
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

    /// Decodes common HTML entities and collapses whitespace.
    private static func clean(_ raw: String) -> String {
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

        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
