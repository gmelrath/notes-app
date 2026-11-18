import Foundation

/// Adds a row to the "Things to Read…" database using Notion's API.
/// The key is in the Keychain (see Secrets); the database comes from Config/Campfire.xcconfig.
enum NotionClient {
    enum NotionError: LocalizedError {
        case missingKey
        case unauthorized
        case databaseNotShared
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Notion isn't set up yet. Add your Notion key in Settings."
            case .unauthorized: "Notion didn't accept the key. Check your Notion key in Settings."
            case .databaseNotShared: "Campfire can’t see your Notion database. In Notion, add the Campfire connection to Things to Read…"
            case .rejected(let message): "Notion said: \(message)"
            }
        }
    }

    private static let apiVersion = "2025-09-03"
    // Notion limits each piece of text to 2,000 characters, counted as UTF-16 units: most emoji count as two.
    // Longer text is sent as several pieces, up to 100 per property or paragraph.
    private static let textLimit = 2000
    private static let pieceLimit = 100
    // A page can be created with at most 100 blocks.
    private static let blockLimit = 100
    // How much of a post or note the Summary column shows when the whole text is in the page body.
    static let previewLength = 200

    static func addPage(for capture: Capture) async throws {
        guard let token = Secrets.value(.notionToken), let dataSourceID = Secrets.setting("NotionDataSourceID") else {
            throw NotionError.missingKey
        }

        var found = try await columns(token: token, dataSourceID: dataSourceID, refresh: false)
        var response = try await post(pageBody(for: capture, columns: found, dataSourceID: dataSourceID), token: token)
        // The remembered columns may be out of date (one deleted or changed type): look again, once.
        if isColumnProblem(response) {
            found = try await columns(token: token, dataSourceID: dataSourceID, refresh: true)
            response = try await post(pageBody(for: capture, columns: found, dataSourceID: dataSourceID), token: token)
        }
        if let error = error(for: response) { throw error }
    }

    private static func post(_ body: [String: Any], token: String) async throws -> ServiceResponse {
        try await ServiceRequest.post(
            URL(string: "https://api.notion.com/v1/pages")!, token: token, body: body,
            headers: ["Notion-Version": apiVersion], timeout: 15
        )
    }

    /// The database's columns: remembered, or looked up in Notion (and then remembered).
    private static func columns(token: String, dataSourceID: String, refresh: Bool) async throws -> NotionColumns {
        if !refresh, let saved = NotionColumnStore.load(for: dataSourceID) { return saved }
        let response = try await ServiceRequest.get(
            URL(string: "https://api.notion.com/v1/data_sources/\(dataSourceID)")!, token: token,
            headers: ["Notion-Version": apiVersion], timeout: 15
        )
        if let error = error(for: response) { throw error }
        guard let description = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let properties = description["properties"] as? [String: Any],
              let columns = NotionColumns.pick(from: properties) else {
            throw NotionError.rejected("couldn't read the database's columns")
        }
        NotionColumnStore.save(columns, for: dataSourceID)
        return columns
    }

    /// Whether Notion turned the page down because of the columns it was sent to.
    static func isColumnProblem(_ response: ServiceResponse) -> Bool {
        response.status == 400 && (response.message ?? "").localizedCaseInsensitiveContains("propert")
    }

    /// The new page: its columns, by ID, and its body. When the database has no Summary or URL
    /// column, that information goes in the page body instead of being lost.
    static func pageBody(for capture: Capture, columns: NotionColumns, dataSourceID: String) -> [String: Any] {
        var properties: [String: Any] = [columns.title: ["title": richText(capture.title)]]
        var blocks: [[String: Any]] = []

        if let url = capture.url {
            if let column = columns.url {
                properties[column] = ["url": url.absoluteString]
            } else {
                blocks.append(linkParagraph(url))
            }
        }

        let summary = summary(for: capture).flatMap { $0.isEmpty ? nil : $0 }
        let pageText = pageText(for: capture)
        if let summary, let column = columns.summary {
            properties[column] = ["rich_text": richText(summary)]
        }
        if let pageText {
            blocks += paragraphs(pageText)
        } else if let summary, columns.summary == nil {
            blocks += paragraphs(summary)
        }

        var body: [String: Any] = [
            "parent": ["type": "data_source_id", "data_source_id": dataSourceID],
            "properties": properties,
        ]
        if !blocks.isEmpty { body["children"] = Array(blocks.prefix(blockLimit)) }
        return body
    }

    private static func linkParagraph(_ url: URL) -> [String: Any] {
        let text: [String: Any] = ["content": url.absoluteString, "link": ["url": url.absoluteString]]
        return ["object": "block", "type": "paragraph", "paragraph": ["rich_text": [["text": text]]]]
    }

    /// What Notion's reply means, or nil when the page was added.
    static func error(for response: ServiceResponse) -> NotionError? {
        guard !response.succeeded else { return nil }
        switch response.status {
        case 401: return .unauthorized
        case 403, 404: return .databaseNotShared
        default: return .rejected(response.message ?? "error \(response.status)")
        }
    }

    // MARK: - What goes where

    /// The Summary column. When the whole post or note is in the page body, this is a short preview.
    /// Otherwise a note written in the app beats the page's description. (The share card keeps its
    /// note for email, so it never sets one on Notion captures.)
    static func summary(for capture: Capture) -> String? {
        if capture.isPost, let post = capture.summary {
            return TitleText.shortened(TitleText.flattened(post), limit: previewLength)
        }
        if capture.url == nil {
            return noteSummary(for: capture).map { TitleText.shortened(TitleText.flattened($0), limit: previewLength) }
        }
        return [capture.note, capture.summary].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// The page body: a post's whole text, or the whole of a note written without a link.
    static func pageText(for capture: Capture) -> String? {
        let text = if capture.isPost {
            capture.summary
        } else if capture.url == nil, let note = noteText(for: capture) {
            // Entries saved before the whole note was kept hold only the lines after the title.
            noteSummary(for: capture) == note ? capture.title + "\n" + note : note
        } else {
            String?.none
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// The note as Notion's Summary shows it. A note written without a link starts with its title
    /// line, which Notion already shows as the Title, so the Summary gets only the lines after it.
    static func noteSummary(for capture: Capture) -> String? {
        guard capture.url == nil else { return capture.note }
        guard let note = noteText(for: capture) else { return nil }
        let firstLine = note.prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        // Entries saved before the whole note was kept hold only the lines after the title.
        guard firstLine == capture.title else { return note }
        return note.drop { $0 != "\n" }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words of an entry without a link: a note written in the app, or text shared to the
    /// share card, which stands in for a note.
    private static func noteText(for capture: Capture) -> String? {
        [capture.note, capture.text].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Notion's text format

    /// `content` as Notion rich text: pieces of up to 2,000 characters, as Notion counts them.
    static func richText(_ content: String) -> [[String: Any]] {
        var pieces: [String] = []
        var piece = ""
        var length = 0
        for character in content {
            let size = character.utf16.count
            if length + size > textLimit {
                pieces.append(piece)
                piece = ""
                length = 0
            }
            piece.append(character)
            length += size
        }
        if !piece.isEmpty || pieces.isEmpty { pieces.append(piece) }
        if pieces.count > pieceLimit {
            pieces = Array(pieces.prefix(pieceLimit))
            pieces[pieceLimit - 1] = fitted(pieces[pieceLimit - 1] + " ", limit: textLimit)
        }
        return pieces.map { ["text": ["content": $0]] }
    }

    /// `text` as page paragraphs, one per line, skipping blank lines. Past Notion's 100-block
    /// limit, the remaining lines share the last paragraph.
    static func paragraphs(_ text: String) -> [[String: Any]] {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > blockLimit {
            lines = Array(lines.prefix(blockLimit - 1)) + [lines.dropFirst(blockLimit - 1).joined(separator: "\n")]
        }
        return lines.map { line in
            ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(line)]]
        }
    }

    /// `content` cut to fit within `limit` as Notion counts it, ending in "…" when shortened.
    /// Cuts between whole characters, so an emoji or accented letter is never split.
    static func fitted(_ content: String, limit: Int) -> String {
        guard content.utf16.count > limit else { return content }
        var result = ""
        var length = 1 // room for the "…"
        for character in content {
            let size = character.utf16.count
            guard length + size <= limit else { break }
            result.append(character)
            length += size
        }
        return result + "…"
    }
}
