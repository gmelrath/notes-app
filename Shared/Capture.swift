import Foundation

/// One entry in the on-phone history: something shared, where it went, and whether it got there.
struct Capture: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case sent
        case failed
    }

    var id = UUID()
    var date = Date()
    var title: String
    var url: URL?
    /// The page's own official address, when it gave one: the same post shared from different apps
    /// often arrives under different links (a short link, a browser link) that all lead here.
    var canonicalURL: URL?
    var summary: String?
    var note: String?
    var text: String?
    var fileNames: [String] = []
    /// A social post: `summary` holds the whole post, which Notion puts in the page body.
    var isPost = false
    var destination: Destination
    var status: Status
    var errorMessage: String?

    var host: String? { url?.displayHost }

    /// The title of a note written without a link: its first line. The whole note stays the body.
    static func title(forNote note: String) -> String {
        String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0 != "\n" })
            .trimmingCharacters(in: .whitespaces)
    }

    /// The link with tracking junk removed, so the same article shared twice is recognised.
    var matchKey: String? { url.map(Capture.matchKey(for:)) }

    /// Every way this entry's page can be recognised: its shared link and its official address.
    var matchKeys: Set<String> { Set([url, canonicalURL].compactMap { $0 }.map(Capture.matchKey(for:))) }

    static func matchKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        var host = (components.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        if host == "twitter.com" { host = "x.com" }

        // A Medium article is the same whichever author or publication address it's shared under;
        // its ID, the hex code at the end, identifies it: ".../title-0583853c5074".
        if host == "medium.com" || host.hasSuffix(".medium.com"),
           let id = components.path.split(separator: "/").last?.split(separator: "-").last,
           (8...16).contains(id.count), id.allSatisfy(\.isHexDigit), id.contains(where: \.isNumber) {
            return "medium.com/p/" + id.lowercased()
        }

        let tracking: Set<String> = [
            "fbclid", "gclid", "igshid", "igsh", "si", "s", "t", "ref", "ref_src", "ref_url", "mc_cid", "mc_eid",
            "trk", "trackingid", "lipi", "rcm", "source", "share", "feature", "smid", "_hsenc", "_hsmi", "mkt_tok",
        ]
        let query = (components.queryItems ?? [])
            .filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !tracking.contains(name)
            }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.fragment = nil

        return host + path + (query.isEmpty ? "" : "?" + query)
    }
}

extension Capture {
    /// Reads an entry saved by any version of Campfire. Only the ID and destination are required;
    /// anything else missing gets a default. When adding a field, read it with `decodeIfPresent`
    /// and a default here, so entries saved before it existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        destination = try container.decode(Destination.self, forKey: .destination)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .distantPast
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        canonicalURL = try container.decodeIfPresent(URL.self, forKey: .canonicalURL)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        fileNames = try container.decodeIfPresent([String].self, forKey: .fileNames) ?? []
        isPost = try container.decodeIfPresent(Bool.self, forKey: .isPost) ?? false
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .failed
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}
