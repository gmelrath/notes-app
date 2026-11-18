import Foundation

/// The database columns the app writes to, by Notion's permanent column IDs. A column keeps its ID
/// when renamed, so sending by ID keeps working after a rename in Notion.
struct NotionColumns: Codable, Equatable {
    var title: String
    var url: String?
    var summary: String?

    /// Picks the columns from a database's description (Notion's "properties", keyed by column name):
    /// - Title: the database's title column. Every database has exactly one.
    /// - URL: the only link column, or else the one named "URL".
    /// - Summary: the text column named "Summary", or else the only text column.
    /// Nil only if there's no title column, which a Notion database always has.
    static func pick(from properties: [String: Any]) -> NotionColumns? {
        let columns = properties.compactMap { name, value -> (name: String, id: String, type: String)? in
            guard let column = value as? [String: Any], let id = column["id"] as? String,
                  let type = column["type"] as? String else { return nil }
            return ((column["name"] as? String) ?? name, id, type)
        }
        func pick(type: String, preferring name: String) -> String? {
            let ofType = columns.filter { $0.type == type }
            if let named = ofType.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return named.id }
            return ofType.count == 1 ? ofType[0].id : nil
        }
        guard let title = columns.first(where: { $0.type == "title" })?.id else { return nil }
        return NotionColumns(title: title, url: pick(type: "url", preferring: "URL"), summary: pick(type: "rich_text", preferring: "Summary"))
    }
}

/// The columns last looked up, kept on the device so most sends don't need an extra request.
/// Remembered per database, so pointing the app at another database looks its columns up afresh.
enum NotionColumnStore {
    private struct Saved: Codable {
        var dataSourceID: String
        var columns: NotionColumns
    }

    static func load(for dataSourceID: String) -> NotionColumns? {
        guard let data = AppGroup.defaults.data(forKey: StoredName.notionColumns.rawValue),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.dataSourceID == dataSourceID else { return nil }
        return saved.columns
    }

    static func save(_ columns: NotionColumns, for dataSourceID: String) {
        let data = try? JSONEncoder().encode(Saved(dataSourceID: dataSourceID, columns: columns))
        AppGroup.defaults.set(data, forKey: StoredName.notionColumns.rawValue)
    }
}
