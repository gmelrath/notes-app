import Foundation

extension Capture {
    /// "Sent to Notion" or "Not sent to Email".
    var statusDescription: String {
        switch status {
        case .sent: "Sent to \(destination.rawValue)"
        case .failed: "Not sent to \(destination.rawValue)"
        }
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
