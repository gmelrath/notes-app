import Foundation

extension Capture {
    /// "Sent to Notion" or "Not sent to Email".
    var statusDescription: String {
        switch status {
        case .sent: "Sent to \(destination.rawValue)"
        case .failed: "Not sent to \(destination.rawValue)"
        }
    }

    /// The warning shown when this link is shared again.
    var duplicateMessage: String {
        switch status {
        case .sent: "Already sent to \(destination.rawValue) \(friendlyDate)."
        case .failed: "You tried this \(friendlyDate), but it didn't send to \(destination.rawValue)."
        }
    }

    /// Why Try again isn't offered for this failed email with files, as shown on `device`
    /// ("iPhone", "iPad"). Kept copies of shared files stay on the device that sent the email.
    func missingFilesMessage(on device: String) -> String {
        guard let sentFrom else {
            return "The files are kept on the device that sent this. Try again there, or share them again."
        }
        if sentFrom == device {
            return "The files are no longer on this \(device). Share them again to try."
        }
        return "The files are kept on your \(sentFrom). Try again there, or share them again."
    }

    /// "today at 5:04 PM", "yesterday at 9:12 AM", or "Oct 12".
    var friendlyDate: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInYesterday(date) { return "yesterday at \(time)" }
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
    }
}

extension URL {
    /// The site's name for display: "example.com" for "https://www.example.com/post".
    var displayHost: String? {
        guard let host = host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
