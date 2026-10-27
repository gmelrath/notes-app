import Foundation

enum Destination: String, Codable, CaseIterable {
    case notion = "Notion"
    case email = "Email"

    var systemImage: String {
        switch self {
        case .notion: "books.vertical"
        case .email: "envelope"
        }
    }
}

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
    var summary: String?
    var note: String?
    var text: String?
    var fileNames: [String] = []
    var destination: Destination
    var status: Status
    var errorMessage: String?

    var host: String? {
        url?.host()?.replacingOccurrences(of: "www.", with: "")
    }

    /// The link with tracking junk removed, so the same article shared twice is recognised.
    var matchKey: String? { url.map(Capture.matchKey(for:)) }

    static func matchKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        var host = (components.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        if host == "twitter.com" { host = "x.com" }

        let tracking: Set<String> = ["fbclid", "gclid", "igshid", "si", "s", "t", "ref", "ref_src", "mc_cid", "mc_eid", "trk", "trackingid", "rcm"]
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
