import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShareCardModel: ObservableObject {
    @Published private(set) var item = SharedItem()
    @Published private(set) var isLoading = true
    @Published private(set) var isFetchingTitle = false
    @Published var title = ""
    @Published private(set) var summary: String?
    /// Whether the link is a social post, whose whole text is in `summary`.
    private var isPost = false
    @Published var note = ""
    @Published private(set) var previous: Capture?
    @Published private(set) var errorMessage: String?
    @Published private(set) var sending: Destination?
    @Published private(set) var sent: Destination?

    /// Retries from this card update the same history entry instead of adding new ones.
    private let captureID = UUID()
    private let close: () -> Void
    /// The page title the sharing app sent along with the link, if any (Safari and many apps do).
    private var sharedTitle: String?

    init(close: @escaping () -> Void) {
        self.close = close
    }

    func canSend(to destination: Destination) -> Bool {
        sending == nil && sent == nil && destination.isSetUp
            && destination.accepts(hasLink: item.url != nil, hasText: !(item.text ?? "").isEmpty, hasFiles: !item.files.isEmpty)
    }

    func cancel() { close() }

    func send(to destination: Destination) async {
        guard canSend(to: destination) else { return }
        sending = destination
        errorMessage = nil
        let attachments = destination.sendsFiles ? item.files.map(\.fileURL) : []
        let (capture, upload) = await Delivery.deliver(makeCapture(for: destination), attachments: attachments)
        sending = nil
        guard capture.status == .sent else {
            errorMessage = capture.errorMessage
            return
        }
        sent = destination
        // Upload while the "Sent" tick shows, so the other device knows about it straight away.
        // If it can't finish, the app uploads it next time it opens.
        try? await Task.sleep(for: .seconds(0.8))
        await upload.value
        close()
    }

    private func makeCapture(for destination: Destination) -> Capture {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Capture(
            id: captureID,
            title: displayTitle,
            url: item.url,
            summary: summary,
            note: destination.includesShareCardNote && !trimmedNote.isEmpty ? trimmedNote : nil,
            text: item.text,
            fileNames: item.files.map(\.name),
            isPost: item.url != nil && isPost,
            destination: destination,
            status: .failed
        )
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return item.url.flatMap { LinkMetadata.title(fromAddress: $0) ?? $0.host() } ?? item.files.first?.name ?? "Untitled"
    }

    // MARK: - Loading what was shared

    func load(from extensionItems: [NSExtensionItem]) async {
        var result = SharedItem()
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        sharedTitle = extensionItems.lazy.compactMap { Self.title(in: $0) }.first

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if result.url == nil { result.url = await loadURL(from: provider) }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let text = await loadText(from: provider) {
                    result.text = [result.text, text].compactMap { $0 }.joined(separator: "\n")
                }
            } else if let file = await loadFile(from: provider) {
                result.files.append(file)
            }
        }

        // Many apps share a post as text with the link inside it.
        if result.url == nil, let text = result.text {
            result.url = LinkMetadata.webLink(in: text)
        }
        // Shared text that is only the link adds nothing.
        if let text = result.text, text.trimmingCharacters(in: .whitespacesAndNewlines) == result.url?.absoluteString {
            result.text = nil
        }

        item = result
        title = defaultTitle(for: result)
        previous = result.url.flatMap { CaptureStore.previous(matching: $0) }
        isLoading = false

        // Another device may have sent this link since this one last synced.
        if let url = result.url {
            Task {
                if await CloudHistory.shared.sync() {
                    previous = CaptureStore.previous(matching: url, excluding: captureID)
                }
            }
        }

        if let url = result.url {
            isFetchingTitle = true
            let details = await LinkMetadata.details(for: url, sharedTitle: sharedTitle)
            isFetchingTitle = false
            // Never replaces a title you've typed.
            if title == defaultTitle(for: result), let fetched = details.title {
                title = fetched
            }
            summary = details.summary
            isPost = details.isPost
        }
    }

    private func defaultTitle(for item: SharedItem) -> String {
        if let text = item.text, item.url == nil {
            return String(text.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces)
        }
        if item.url == nil, let file = item.files.first {
            return file.name
        }
        return item.url == nil ? "" : sharedTitle ?? ""
    }

    /// A title the sharing app put on the item. Ignored when it's really the link, or shared text.
    private static func title(in item: NSExtensionItem) -> String? {
        guard let raw = item.attributedTitle?.string ?? item.attributedContentText?.string else { return nil }
        let title = TitleText.flattened(raw)
        guard !title.isEmpty, raw.count <= 300, !raw.contains("\n"),
              !title.lowercased().hasPrefix("http://"), !title.lowercased().hasPrefix("https://") else { return nil }
        return TitleText.shortened(title, limit: 150)
    }


    private func loadURL(from provider: NSItemProvider) async -> URL? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
        if let url = item as? URL { return url }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
        return item as? String
    }

    /// Copies a shared file somewhere we control; the system's copy disappears after the callback.
    private func loadFile(from provider: NSItemProvider) async -> SharedFile? {
        guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) else {
            return nil
        }
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                // Name the copy as the user sees it, since it becomes the email attachment's name.
                let name = suggestedName.map { name in
                    name.contains(".") || url.pathExtension.isEmpty ? name : "\(name).\(url.pathExtension)"
                } ?? url.lastPathComponent
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let destination = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                    let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    continuation.resume(returning: SharedFile(
                        name: name,
                        fileURL: destination,
                        byteCount: Int64(size)
                    ))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
