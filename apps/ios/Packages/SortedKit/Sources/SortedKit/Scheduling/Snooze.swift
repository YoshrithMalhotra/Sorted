import Foundation

/// The snooze choices on a Today row: 1 hour, tonight and tomorrow.
public enum SnoozeOption: String, CaseIterable, Sendable {
    case oneHour
    case tonight
    case tomorrow

    public static let tonightTime = TimeOfDay(hour: 20)

    public var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .tonight: "Tonight"
        case .tomorrow: "Tomorrow"
        }
    }

    /// When the snoozed item comes back, or nil when the option doesn't apply
    /// (it's already past 8 PM, so "tonight" is gone).
    public func wakeDate(now: Date, in timeZone: TimeZone, defaultTime: TimeOfDay) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .tonight:
            let tonight = Self.tonightTime.on(now, in: timeZone)
            return tonight > now ? tonight : nil
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return defaultTime.on(tomorrow, in: timeZone)
        }
    }
}
