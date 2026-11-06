import Foundation

/// A time of day, such as the user's default reminder time (9:00 AM).
public struct TimeOfDay: Hashable, Sendable, Codable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public static let defaultReminder = TimeOfDay(hour: 9)

    /// Minutes since midnight, for storing in `UserDefaults`.
    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public init(minutesSinceMidnight minutes: Int) {
        self.init(hour: minutes / 60 % 24, minute: minutes % 60)
    }

    /// This time on the local day that contains `date`.
    public func on(_ date: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
}

/// Converts the API's local date-times ("2026-11-10T09:00:00", no offset) to
/// and from `Date` in the user's time zone.
public enum LocalDateTime {
    public static func date(from string: String, in timeZone: TimeZone) -> Date? {
        // A string with an offset or "Z" is already an instant.
        if let instant = try? Date(string, strategy: .iso8601) { return instant }

        let parts = string.split(separator: "T", maxSplits: 1)
        let dateParts = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard dateParts.count == 3 else { return nil }
        var timeParts = parts.count == 2 ? parts[1].split(separator: ":").compactMap { Int($0.prefix(2)) } : []
        while timeParts.count < 3 { timeParts.append(0) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: dateParts[0], month: dateParts[1], day: dateParts[2],
            hour: timeParts[0], minute: timeParts[1], second: timeParts[2]
        ))
    }

    public static func string(from date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}
