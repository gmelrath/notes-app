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
        reload()
    }

    func retry(_ capture: Capture) async -> Capture {
        var updated = capture
        updated.date = .now
        do {
            try await Sender.send(capture, to: capture.destination)
            updated.status = .sent
            updated.errorMessage = nil
        } catch {
            updated.status = .failed
            updated.errorMessage = error.localizedDescription
        }
        CaptureStore.save(updated)
        reload()
        return updated
    }
}
