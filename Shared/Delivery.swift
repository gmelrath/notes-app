import Foundation

/// The one send process, used by the compose screen, the share card and Try again in Sent:
/// send, record whether it got there, save it to the history, look after any shared files,
/// and start the iCloud sync. What happens afterwards (clearing the form, closing the card,
/// refreshing the list) is up to each caller.
@MainActor
enum Delivery {
    /// Sends `capture` to its destination and saves the outcome. Files that didn't get there are
    /// kept on this device so Sent can retry them; once sent, kept copies are removed.
    /// Returns the saved entry and the sync it started, which a caller about to close can wait for.
    /// `sync` defaults to uploading the change; the app passes its own, which also refreshes screens.
    @discardableResult
    static func deliver(
        _ capture: Capture,
        attachments: [URL] = [],
        sync: @escaping () async -> Void = { await CloudHistory.shared.sync(includePull: false) }
    ) async -> (capture: Capture, sync: Task<Void, Never>) {
        var result = capture
        do {
            try await Sender.send(capture, to: capture.destination, attachments: attachments)
            result.status = .sent
            result.errorMessage = nil
            AttachmentStore.remove(for: [capture.id])
        } catch {
            result.status = .failed
            result.errorMessage = error.localizedDescription
            // The share sheet's copies vanish when the card closes. A retry already sends the kept copies.
            if !attachments.isEmpty, Set(attachments) != Set(AttachmentStore.files(for: capture.id)) {
                AttachmentStore.save(attachments, for: capture.id)
            }
        }
        CaptureStore.save(result)
        return (result, Task { await sync() })
    }
}
