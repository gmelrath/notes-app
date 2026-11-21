import Foundation

/// Sends a capture to the address in Settings using Resend's API.
/// The key is in the Keychain (see Secrets).
enum EmailClient {
    enum EmailError: LocalizedError {
        case missingKey
        case unauthorized
        case notAccountAddress
        case attachmentsTooLarge
        case unreadableAttachment(String)
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Email isn't set up yet. Add your Resend key in Settings."
            case .unauthorized: "Resend didn't accept the key. Check your Resend key in Settings."
            case .notAccountAddress: "Resend can only send to the address you signed up with. Use that address in Settings."
            case .attachmentsTooLarge: "The files are too large to email (25 MB limit)."
            case .unreadableAttachment(let name): "Couldn't read \(name). Try sharing it again."
            case .rejected(let message): "Resend said: \(message)"
            }
        }
    }

    // Resend's shared sending address. It can only deliver to the Resend account's own email.
    private static let from = "Stowaway <onboarding@resend.dev>"
    private static let attachmentLimit: Int64 = 25 * 1024 * 1024

    static func send(_ capture: Capture, to address: String, attachments: [URL]) async throws {
        guard let key = Secrets.value(.resendAPIKey) else { throw EmailError.missingKey }

        var body: [String: Any] = [
            "from": from,
            "to": [address],
            "subject": capture.title,
            "text": plainText(for: capture),
            "html": html(for: capture),
        ]
        if !attachments.isEmpty {
            body["attachments"] = try encoded(attachments)
        }

        let response = try await ServiceRequest.post(
            URL(string: "https://api.resend.com/emails")!, token: key, body: body,
            // Lets a retry of the same capture be recognised by Resend instead of sending twice.
            headers: ["Idempotency-Key": capture.id.uuidString], timeout: 60
        )
        if let error = error(for: response) { throw error }
    }

    /// What Resend's reply means, or nil when the email was accepted.
    static func error(for response: ServiceResponse) -> EmailError? {
        guard !response.succeeded else { return nil }
        let message = response.message ?? ""
        switch response.status {
        case 401: return .unauthorized
        case 403 where message.localizedCaseInsensitiveContains("own email"): return .notAccountAddress
        case 403: return .unauthorized
        default: return .rejected(message.isEmpty ? "error \(response.status)" : message)
        }
    }

    // MARK: - Message body

    private static func plainText(for capture: Capture) -> String {
        [
            capture.note,
            capture.url?.absoluteString,
            capture.summary,
            capture.text,
            capture.fileNames.isEmpty ? nil : "Attached: " + capture.fileNames.joined(separator: ", "),
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func html(for capture: Capture) -> String {
        var parts: [String] = []
        if let note = capture.note, !note.isEmpty {
            parts.append("<p style=\"font-size:16px\">\(escape(note).replacingOccurrences(of: "\n", with: "<br>"))</p>")
        }
        if let url = capture.url {
            let label = escape(capture.host ?? url.absoluteString)
            parts.append("<p><a href=\"\(escape(url.absoluteString))\">\(label)</a></p>")
        }
        if let summary = capture.summary, !summary.isEmpty {
            parts.append("<p style=\"color:#666\">\(escape(summary).replacingOccurrences(of: "\n", with: "<br>"))</p>")
        }
        if let text = capture.text, !text.isEmpty {
            parts.append("<blockquote style=\"color:#444;border-left:3px solid #ddd;margin:0;padding-left:12px\">\(escape(text).replacingOccurrences(of: "\n", with: "<br>"))</blockquote>")
        }
        return "<div style=\"font-family:-apple-system,Helvetica,sans-serif;line-height:1.4\">\(parts.joined())</div>"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Attachments

    private static func encoded(_ files: [URL]) throws -> [[String: String]] {
        let total = files.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard total <= attachmentLimit else { throw EmailError.attachmentsTooLarge }

        return try files.map { url in
            guard let data = try? Data(contentsOf: url) else {
                throw EmailError.unreadableAttachment(url.lastPathComponent)
            }
            return ["filename": url.lastPathComponent, "content": data.base64EncodedString()]
        }
    }
}
