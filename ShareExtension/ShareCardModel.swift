import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShareCardModel: ObservableObject {
    @Published private(set) var item = SharedItem()
    @Published private(set) var isLoading = true
    @Published private(set) var isFetchingTitle = false
    @Published var title = ""
    @Published private(set) var summary: String?
    @Published var note = ""
    @Published private(set) var previous: Capture?
    @Published private(set) var errorMessage: String?
    @Published private(set) var sending: Destination?
    @Published private(set) var sent: Destination?

    let hasEmailAddress = AppSettings.emailAddress != nil

    /// Retries from this card update the same history entry instead of adding new ones.
    private let captureID = UUID()
    private let close: () -> Void

    init(close: @escaping () -> Void) {
        self.close = close
    }

    var canSendToNotion: Bool { item.url != nil && sending == nil && sent == nil }
    var canSendByEmail: Bool { !item.isEmpty && hasEmailAddress && sending == nil && sent == nil }

    func cancel() { close() }

    func send(to destination: Destination) async {
        guard sending == nil, sent == nil else { return }
        sending = destination
        errorMessage = nil
        var capture = makeCapture(for: destination)

        do {
            try await Sender.send(capture, to: destination)
            capture.status = .sent
            CaptureStore.save(capture)
            sending = nil
            sent = destination
            try? await Task.sleep(for: .seconds(0.8))
            close()
        } catch {
            capture.status = .failed
            capture.errorMessage = error.localizedDescription
            CaptureStore.save(capture)
            sending = nil
            errorMessage = error.localizedDescription
        }
    }

    private func makeCapture(for destination: Destination) -> Capture {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return Capture(
            id: captureID,
            title: displayTitle,
            url: item.url,
            summary: summary,
            note: destination == .email && !trimmedNote.isEmpty ? trimmedNote : nil,
            text: item.text,
            fileNames: item.files.map(\.name),
            destination: destination,
            status: .failed
        )
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return item.url?.host() ?? item.files.first?.name ?? "Untitled"
    }

    // MARK: - Loading what was shared

    func load(from extensionItems: [NSExtensionItem]) async {
        var result = SharedItem()
        let providers = extensionItems.flatMap { $0.attachments ?? [] }

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
            result.url = firstLink(in: text)
        }
        // Shared text that is only the link adds nothing.
        if let text = result.text, text.trimmingCharacters(in: .whitespacesAndNewlines) == result.url?.absoluteString {
            result.text = nil
        }

        item = result
        title = defaultTitle(for: result)
        previous = result.url.flatMap { CaptureStore.previous(matching: $0) }
        isLoading = false

        if let url = result.url {
            isFetchingTitle = true
            let metadata = await LinkMetadata.fetch(for: url)
            isFetchingTitle = false
            if let fetched = metadata.title, !fetched.isEmpty, title == defaultTitle(for: result) {
                title = fetched
            }
            summary = metadata.description
        }
    }

    private func defaultTitle(for item: SharedItem) -> String {
        if let text = item.text, item.url == nil {
            return String(text.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces)
        }
        if item.url == nil, let file = item.files.first {
            return file.name
        }
        return ""
    }

    private func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
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
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let destination = folder.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: destination)
                    let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    continuation.resume(returning: SharedFile(
                        name: suggestedName.map { name in
                            name.contains(".") ? name : "\(name).\(url.pathExtension)"
                        } ?? url.lastPathComponent,
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
