import Foundation
import Testing
@testable import Campfire

@Suite("History file")
struct HistoryFileTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    private func entry(_ id: UUID, destination: String = "Notion", extra: String = "") -> String {
        #"{"id":"\#(id)","date":"2026-11-01T10:00:00Z","title":"Entry","destination":"\#(destination)","status":"sent","fileNames":[]\#(extra)}"#
    }

    @Test func loadsTodaysFormat() throws {
        let a = Capture(title: "Article", url: URL(string: "https://a.com/x"), destination: .notion, status: .sent)
        let b = Capture(title: "Note", note: "hello", destination: .email, status: .failed, errorMessage: "offline")
        let file = try HistoryFile(data: try CaptureStore.encoder.encode([a, b]))
        #expect(file.captures.map(\.id) == [a.id, b.id])
        #expect(file.captures[1].errorMessage == "offline")
        #expect(file.unreadable.isEmpty)
    }

    @Test func oneUnreadableEntryDoesNotHideTheOthers() throws {
        let good = UUID(), future = UUID()
        let file = try HistoryFile(data: json("[\(entry(good)),\(entry(future, destination: "Slack"))]"))
        #expect(file.captures.map(\.id) == [good])
        #expect(file.unreadable.count == 1)
    }

    @Test func missingFieldsGetDefaults() throws {
        let id = UUID()
        let capture = try #require(try HistoryFile(data: json(#"[{"id":"\#(id)","destination":"Email"}]"#)).captures.first)
        #expect(capture.title == "Untitled")
        #expect(capture.status == .failed)
        #expect(capture.fileNames.isEmpty)
        #expect(!capture.isPost)
    }

    @Test func writingBackKeepsUnreadableEntriesAndUnknownFields() throws {
        let tagged = UUID(), future = UUID()
        let file = try HistoryFile(data: json("[\(entry(tagged, extra: #","tags":["ai"]"#)),\(entry(future, destination: "Slack"))]"))
        let written = try #require(try JSONSerialization.jsonObject(with: file.encoded()) as? [[String: Any]])
        #expect(written.count == 2)
        #expect(written.contains { $0["destination"] as? String == "Slack" })
        #expect((written.first { $0["id"] as? String == tagged.uuidString }?["tags"] as? [String]) == ["ai"])
    }

    @Test func editsToKnownFieldsAreSaved() throws {
        let id = UUID()
        var file = try HistoryFile(data: json("[\(entry(id, extra: #","tags":["ai"]"#))]"))
        file.captures[0].title = "Renamed"
        let written = try #require(try JSONSerialization.jsonObject(with: file.encoded()) as? [[String: Any]])
        #expect(written.first?["title"] as? String == "Renamed")
    }

    @Test func deletingReachesUnreadableEntries() throws {
        let future = UUID()
        var file = try HistoryFile(data: json("[\(entry(future, destination: "Slack"))]"))
        file.remove([future])
        #expect(file.unreadable.isEmpty)
    }

    @Test("A damaged file is refused, not read as empty", arguments: ["{not json", #"{"a":1}"#])
    func damagedFile(text: String) {
        #expect(throws: (any Error).self) { try HistoryFile(data: Data(text.utf8)) }
    }

    @Test func anEmptyListIsFine() throws {
        #expect(try HistoryFile(data: json("[]")).captures.isEmpty)
    }
}

@Suite("Merging iCloud changes")
struct MergeTests {
    private func capture(_ title: String, id: UUID = UUID()) -> Capture {
        Capture(id: id, title: title, destination: .notion, status: .sent)
    }

    @Test func addsNewEntries() {
        var file = HistoryFile()
        let new = capture("From iPad")
        let changed = file.merge(saved: [new], unreadable: [], deleted: [], keeping: [])
        #expect(changed)
        #expect(file.captures == [new])
    }

    @Test func identicalEntriesAreNotAChange() {
        let same = capture("Same")
        var file = HistoryFile()
        file.captures = [same]
        let changed = file.merge(saved: [same], unreadable: [], deleted: [], keeping: [])
        #expect(!changed)
    }

    @Test func updatesChangedEntries() {
        let id = UUID()
        var file = HistoryFile()
        file.captures = [capture("Old", id: id)]
        let changed = file.merge(saved: [capture("New", id: id)], unreadable: [], deleted: [], keeping: [])
        #expect(changed)
        #expect(file.captures.first?.title == "New")
    }

    @Test func pendingLocalChangesAreNotOverwritten() {
        let id = UUID()
        var file = HistoryFile()
        file.captures = [capture("Edited here", id: id)]
        let changed = file.merge(saved: [capture("Older copy", id: id)], unreadable: [], deleted: [id], keeping: [id])
        #expect(!changed)
        #expect(file.captures.first?.title == "Edited here")
    }

    @Test func deletesEntriesFromOtherDevices() {
        let id = UUID()
        var file = HistoryFile()
        file.captures = [capture("Gone", id: id), capture("Stays")]
        let changed = file.merge(saved: [], unreadable: [], deleted: [id], keeping: [])
        #expect(changed)
        #expect(file.captures.map(\.title) == ["Stays"])
    }

    @Test func keepsEntriesFromNewerVersions() throws {
        let id = UUID()
        var file = HistoryFile()
        file.captures = [capture("Old local copy", id: id)]
        let payload = Data(#"{"id":"\#(id)","title":"From a newer app","destination":"Slack","status":"sent"}"#.utf8)
        let changed = file.merge(saved: [], unreadable: [payload], deleted: [], keeping: [])
        #expect(changed)
        #expect(file.captures.isEmpty)
        #expect(file.unreadable.count == 1)
    }
}
