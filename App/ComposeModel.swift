import UIKit
import UniformTypeIdentifiers

/// State for the screen the app opens on: write a note, optionally with a link, and send it.
@MainActor
final class ComposeModel: ObservableObject {
    @Published var linkText = "" {
        didSet { if linkText != oldValue { linkChanged() } }
    }
    @Published var title = ""
    @Published var note = ""
    @Published private(set) var summary: String?
    /// Whether the link is a social post, whose whole text is in `summary`.
    private var isPost = false
    @Published private(set) var isFetchingTitle = false
    @Published private(set) var previous: Capture?
    @Published private(set) var errorMessage: String?
    @Published private(set) var confirmation: String?
    @Published private(set) var sending: Destination?
    @Published private(set) var sent: Destination?

    /// Retries from this screen update the same history entry instead of adding new ones.
    private var captureID = UUID()
    private var fetchTask: Task<Void, Never>?
    /// The title last filled in automatically, so a title the user typed is never replaced.
    private var fetchedTitle = ""

    var url: URL? { LinkMetadata.webLink(in: linkText) }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    func canSend(to destination: Destination) -> Bool {
        sending == nil && sent == nil && destination.isSetUp
            && destination.accepts(hasLink: url != nil, hasText: !trimmedNote.isEmpty, hasFiles: false)
    }

    /// Whether the clipboard holds a link or text. Checking this doesn't trigger iOS's "Allow Paste" prompt.
    @Published private(set) var canPaste = false

    func refreshPasteboard() {
        canPaste = UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings
    }

    /// Apps copy links either as a URL or as plain text; accept whichever is there.
    func paste(_ providers: [NSItemProvider]) async {
        for provider in providers {
            if let text = await Self.text(from: provider) {
                linkText = LinkMetadata.webLink(in: text)?.absoluteString ?? text
                return
            }
        }
    }

    /// The clipboard item as text, preferring a web link. `loadObject` decodes the item the way the
    /// copying app meant it; reading the raw type can hand back a temporary file instead.
    private static func text(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: URL.self),
           let url = await load(URL.self, from: provider), !url.isFileURL {
            return url.absoluteString
        }
        if provider.canLoadObject(ofClass: String.self) {
            return await load(String.self, from: provider)
        }
        return nil
    }

    private static func load<T: _ObjectiveCBridgeable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
    where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { object, _ in
                continuation.resume(returning: object)
            }
        }
    }

    func clearLink() {
        linkText = ""
    }

    func send(to destination: Destination) async {
        guard canSend(to: destination) else { return }
        sending = destination
        errorMessage = nil
        confirmation = nil
        let (capture, _) = await Delivery.deliver(makeCapture(for: destination)) { await syncHistory() }
        sending = nil
        guard capture.status == .sent else {
            errorMessage = capture.errorMessage
            return
        }
        sent = destination
        try? await Task.sleep(for: .seconds(0.8))
        reset()
        confirmation = "Sent to \(destination.rawValue)."
    }

    func dismissConfirmation() {
        confirmation = nil
    }

    /// The note always travels whole. Without a link, its first line also becomes the title,
    /// so an email's subject is the first line and its body the entire note.
    private func makeCapture(for destination: Destination) -> Capture {
        var title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String? = trimmedNote.isEmpty ? nil : trimmedNote

        if url == nil {
            title = Capture.title(forNote: trimmedNote)
        } else if title.isEmpty {
            title = url.flatMap { LinkMetadata.title(fromAddress: $0) ?? $0.host() } ?? "Untitled"
        }

        return Capture(
            id: captureID,
            title: title,
            url: url,
            summary: summary,
            note: body,
            isPost: url != nil && isPost,
            destination: destination,
            status: .failed
        )
    }

    private func reset() {
        fetchTask?.cancel()
        linkText = ""
        title = ""
        note = ""
        fetchedTitle = ""
        summary = nil
        isPost = false
        previous = nil
        errorMessage = nil
        sent = nil
        captureID = UUID()
    }

    /// Checks the history for an earlier send of this link, as on the share card. Called again
    /// when your other device's history arrives, so a link sent there moments ago is flagged.
    func refreshPrevious() {
        previous = url.flatMap { CaptureStore.previous(matching: $0, excluding: captureID) }
    }

    // MARK: - Link handling

    private func linkChanged() {
        fetchTask?.cancel()
        summary = nil
        isPost = false
        errorMessage = nil
        if title == fetchedTitle { title = "" }
        fetchedTitle = ""

        guard let url else {
            previous = nil
            isFetchingTitle = false
            return
        }
        refreshPrevious()

        fetchTask = Task {
            // Wait for typing to settle before fetching.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isFetchingTitle = true
            let details = await LinkMetadata.details(for: url)
            guard !Task.isCancelled else { return }
            isFetchingTitle = false
            summary = details.summary
            isPost = details.isPost
            // Never replaces a title you've typed.
            if let fetched = details.title, title.isEmpty {
                title = fetched
                fetchedTitle = fetched
            }
        }
    }
}
