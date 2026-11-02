import Foundation

/// State for the screen the app opens on: write a note, optionally with a link, and send it.
@MainActor
final class ComposeModel: ObservableObject {
    @Published var linkText = "" {
        didSet { if linkText != oldValue { linkChanged() } }
    }
    @Published var title = ""
    @Published var note = ""
    @Published private(set) var summary: String?
    @Published private(set) var isFetchingTitle = false
    @Published private(set) var previous: Capture?
    @Published private(set) var errorMessage: String?
    @Published private(set) var confirmation: String?
    @Published private(set) var sending: Destination?
    @Published private(set) var sent: Destination?

    var hasEmailAddress: Bool { AppSettings.emailAddress != nil }

    /// Retries from this screen update the same history entry instead of adding new ones.
    private var captureID = UUID()
    private var fetchTask: Task<Void, Never>?
    /// The title last filled in automatically, so a title the user typed is never replaced.
    private var fetchedTitle = ""

    var url: URL? { Self.link(in: linkText) }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasContent: Bool { url != nil || !trimmedNote.isEmpty }

    var canSend: Bool { hasContent && sending == nil && sent == nil }
    var canSendByEmail: Bool { canSend && hasEmailAddress }

    func paste(_ strings: [String]) {
        guard let text = strings.first else { return }
        linkText = Self.link(in: text)?.absoluteString ?? text
    }

    func clearLink() {
        linkText = ""
    }

    func send(to destination: Destination) async {
        guard canSend else { return }
        sending = destination
        errorMessage = nil
        confirmation = nil
        var capture = makeCapture(for: destination)

        do {
            try await Sender.send(capture, to: destination)
            capture.status = .sent
            CaptureStore.save(capture)
            sending = nil
            sent = destination
            try? await Task.sleep(for: .seconds(0.8))
            reset()
            confirmation = "Sent to \(destination.rawValue)."
        } catch {
            capture.status = .failed
            capture.errorMessage = error.localizedDescription
            CaptureStore.save(capture)
            sending = nil
            errorMessage = error.localizedDescription
        }
    }

    func dismissConfirmation() {
        confirmation = nil
    }

    /// With a link, the note travels as-is. Without one, its first line becomes the title and the rest the body.
    private func makeCapture(for destination: Destination) -> Capture {
        var title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: String? = trimmedNote.isEmpty ? nil : trimmedNote

        if url == nil {
            let lines = trimmedNote.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            title = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
            let rest = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            body = rest.isEmpty ? nil : rest
        } else if title.isEmpty {
            title = url?.host() ?? "Untitled"
        }

        return Capture(
            id: captureID,
            title: title,
            url: url,
            summary: summary,
            note: body,
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
        previous = nil
        errorMessage = nil
        sent = nil
        captureID = UUID()
    }

    // MARK: - Link handling

    private func linkChanged() {
        fetchTask?.cancel()
        summary = nil
        errorMessage = nil
        if title == fetchedTitle { title = "" }
        fetchedTitle = ""

        guard let url else {
            previous = nil
            isFetchingTitle = false
            return
        }
        previous = CaptureStore.previous(matching: url)

        fetchTask = Task {
            // Wait for typing to settle before fetching.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isFetchingTitle = true
            let metadata = await LinkMetadata.fetch(for: url)
            guard !Task.isCancelled else { return }
            isFetchingTitle = false
            summary = metadata.description
            if let fetched = metadata.title, !fetched.isEmpty, title.isEmpty {
                title = fetched
                fetchedTitle = fetched
            }
        }
    }

    /// A web link typed or pasted on its own, with or without "https://", or the first link inside longer text.
    static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let match = detector?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard let url = match?.url, url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}
