import Foundation

/// Sends a capture to the address in Settings using Resend's API.
/// The key comes from Config/Secrets.xcconfig via each target's Info.plist.
enum EmailClient {
    enum EmailError: LocalizedError {
        case missingKey
        case unauthorized
        case notAccountAddress
        case attachmentsTooLarge
        case unreadableAttachment(String)
        case offline
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: "Email isn't set up yet. Add your Resend key to Config/Secrets.xcconfig."
            case .unauthorized: "Resend didn't accept the key. Check Config/Secrets.xcconfig."
            case .notAccountAddress: "Resend can only send to the address you signed up with. Use that address in Settings."
            case .attachmentsTooLarge: "The files are too large to email (25 MB limit)."
            case .unreadableAttachment(let name): "Couldn't read \(name). Try sharing it again."
            case .offline: "No internet connection. Try again when you're back online."
            case .rejected(let message): "Resend said: \(message)"
            }
        }
    }

    // Resend's shared sending address. It can only deliver to the Resend account's own email.
    private static let from = "Campfire <onboarding@resend.dev>"
    private static let attachmentLimit: Int64 = 25 * 1024 * 1024

    static func send(_ capture: Capture, to address: String, attachments: [URL]) async throws {
        guard let key = Secrets.value("ResendAPIKey") else { throw EmailError.missingKey }

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

        var request = URLRequest(url: URL(string: "https://api.resend.com/emails")!, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Lets a retry of the same capture be recognised by Resend instead of sending twice.
        request.setValue(capture.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw EmailError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(status) else { return }

        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
        switch status {
        case 401: throw EmailError.unauthorized
        case 403 where message.localizedCaseInsensitiveContains("own email"): throw EmailError.notAccountAddress
        case 403: throw EmailError.unauthorized
        default: throw EmailError.rejected(message.isEmpty ? "error \(status)" : message)
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
            parts.append("<p style=\"color:#666\">\(escape(summary))</p>")
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
