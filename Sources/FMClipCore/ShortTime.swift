import Foundation

/// The short time of a list row: the time for today, "Yesterday", else a short date ("Nov 18"), with the year for an
/// earlier year ("Nov 18, 2025").
public enum ShortTime {
    public static func format(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            time.dateStyle = .none
            time.timeStyle = .short
            return time.string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        time.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return time.string(from: date)
    }

    /// The date of an ISO 8601 time from index.json (with or without fractional seconds).
    public static func parse(_ iso: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = parser.date(from: iso) { return d }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: iso)
    }
}
