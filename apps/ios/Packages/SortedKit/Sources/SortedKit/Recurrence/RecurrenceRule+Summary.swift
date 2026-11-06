import Foundation

extension RecurrenceRule {
    /// A short English description for confirmation cards and rows,
    /// such as "Monthly on the 1st" or "Every 2 weeks on Tue, Thu".
    public var summary: String {
        var text: String
        switch (frequency, interval) {
        case (.hourly, 1): text = "Every hour"
        case (.hourly, _): text = "Every \(interval) hours"
        case (.daily, 1): text = "Daily"
        case (.daily, _): text = "Every \(interval) days"
        case (.weekly, 1): text = "Weekly"
        case (.weekly, _): text = "Every \(interval) weeks"
        case (.monthly, 1): text = "Monthly"
        case (.monthly, _): text = "Every \(interval) months"
        case (.yearly, 1): text = "Yearly"
        case (.yearly, _): text = "Every \(interval) years"
        }

        if !byDay.isEmpty, byDay.allSatisfy({ $0.ordinal == nil }),
                  Set(byDay.map(\.weekday)) == [.monday, .tuesday, .wednesday, .thursday, .friday] {
            text += " on weekdays"
        } else if !byDay.isEmpty {
            text += " on " + byDay.sorted { $0.weekday < $1.weekday }.map(Self.describe).joined(separator: ", ")
        }

        let months = Self.english.shortMonthSymbols
        if frequency == .yearly, byMonth.count == 1, byDay.isEmpty, byMonthDay.count == 1, byMonthDay[0] > 0 {
            // "Yearly on Mar 10" reads better than "on the 10th in Mar".
            text += " on \(months[byMonth[0] - 1]) \(byMonthDay[0])"
        } else {
            if !byMonthDay.isEmpty {
                text += (byDay.isEmpty ? " on the " : ", the ") + byMonthDay.map(Self.describeMonthDay).joined(separator: ", ")
            }
            if !byMonth.isEmpty {
                text += " in " + byMonth.sorted().map { months[$0 - 1] }.joined(separator: ", ")
            }
        }
        if !byHour.isEmpty {
            text += " at " + byHour.sorted().map(Self.describeHour).joined(separator: ", ")
        }
        if let count {
            text += count == 1 ? ", once" : ", \(count) times"
        }
        if let until {
            let digits = until.rruleValue.prefix(8)
            text += ", until \(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
        }
        return text
    }

    /// The summary is English for now, so its symbols are too.
    private static let english: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static func describe(_ entry: WeekdayNum) -> String {
        let name = english.shortWeekdaySymbols[entry.weekday.rawValue - 1]
        guard let ordinal = entry.ordinal else { return name }
        switch ordinal {
        case -1: return "the last \(name)"
        case -2: return "the second-to-last \(name)"
        default: return "the \(ordinalString(ordinal)) \(name)"
        }
    }

    private static func describeMonthDay(_ day: Int) -> String {
        switch day {
        case -1: "last day"
        case -2: "second-to-last day"
        case ..<0: "\(ordinalString(-day)) day from the end"
        default: ordinalString(day)
        }
    }

    private static func describeHour(_ hour: Int) -> String {
        switch hour {
        case 0: "12 AM"
        case 12: "12 PM"
        case 1..<12: "\(hour) AM"
        default: "\(hour - 12) PM"
        }
    }

    static func ordinalString(_ number: Int) -> String {
        let suffix: String
        switch (number % 100, number % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}
