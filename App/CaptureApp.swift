import SwiftUI

@main
struct CaptureApp: App {
    var body: some Scene {
        WindowGroup {
            HistoryView()
        }
    }
}

/// Keeps the app's copy of the history in step with the file the share card writes to.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var captures: [Capture] = []

    func reload() {
        captures = CaptureStore.load()
    }

    func delete(_ ids: Set<Capture.ID>) {
        CaptureStore.delete(ids: ids)
        AttachmentStore.remove(for: ids)
        reload()
    }

    /// Retry needs the kept copies of any shared files; without them, files would silently go missing.
    func canRetry(_ capture: Capture) -> Bool {
        capture.destination == .notion || capture.fileNames.isEmpty || !AttachmentStore.files(for: capture.id).isEmpty
    }

    func retry(_ capture: Capture) async -> Capture {
        var updated = capture
        updated.date = .now
        do {
            try await Sender.send(capture, to: capture.destination, attachments: AttachmentStore.files(for: capture.id))
            updated.status = .sent
            updated.errorMessage = nil
            AttachmentStore.remove(for: [capture.id])
        } catch {
            updated.status = .failed
            updated.errorMessage = error.localizedDescription
        }
        CaptureStore.save(updated)
        reload()
        return updated
    }
}
