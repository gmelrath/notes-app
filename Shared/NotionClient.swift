import Foundation

/// Adds a row to the "Things to Read…" database using Notion's API.
/// The key and database come from Config/Capture.xcconfig via each target's Info.plist.
enum NotionClient {
    enum NotionError: LocalizedError {
        case missingKey
        case unauthorized
        case databaseNotShared
        case offline
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Notion isn't set up yet. Add your Notion key to Config/Secrets.xcconfig."
            case .unauthorized: "Notion didn't accept the key. Check Config/Secrets.xcconfig."
            case .databaseNotShared: "Capture can't see your Notion database. In Notion, add the Capture connection to Things to Read…"
            case .offline: "No internet connection. Try again when you're back online."
            case .rejected(let message): "Notion said: \(message)"
            }
        }
    }

    private static let apiVersion = "2025-09-03"
    // Notion limits each block of text to 2,000 characters.
    private static let textLimit = 2000

    static func addPage(for capture: Capture) async throws {
        guard let token = infoValue("NotionToken"), let dataSourceID = infoValue("NotionDataSourceID") else {
            throw NotionError.missingKey
        }

        var properties: [String: Any] = [
            "Title": ["title": [text(capture.title)]],
        ]
        if let url = capture.url {
            properties["URL"] = ["url": url.absoluteString]
        }
        if let summary = capture.summary, !summary.isEmpty {
            properties["Summary"] = ["rich_text": [text(summary)]]
        }
        let body: [String: Any] = [
            "parent": ["type": "data_source_id", "data_source_id": dataSourceID],
            "properties": properties,
        ]

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw NotionError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return }

        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
        switch status {
        case 401: throw NotionError.unauthorized
        case 403, 404: throw NotionError.databaseNotShared
        default: throw NotionError.rejected(message ?? "error \(status)")
        }
    }

    private static func text(_ content: String) -> [String: Any] {
        ["text": ["content": String(content.prefix(textLimit))]]
    }

    /// A value from Info.plist, ignoring blanks and the example placeholder.
    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("paste-") ? nil : trimmed
    }
}
