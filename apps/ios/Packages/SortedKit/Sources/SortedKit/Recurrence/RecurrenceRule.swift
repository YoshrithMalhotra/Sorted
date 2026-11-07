import Foundation

/// A recurrence rule in the RFC 5545 subset Sorted supports.
///
/// Supported: `FREQ` (HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY), `INTERVAL`,
/// `BYDAY` (with ordinals such as `-1FR` for MONTHLY and YEARLY), `BYMONTHDAY`
/// (including negatives such as `-1`), `BYMONTH`, `BYHOUR`, `UNTIL`, `COUNT`
/// and `WKST=MO`. Anything else is rejected with `.unsupported`, so a rule the
/// app can't expand never gets saved.
///
/// The same subset is validated by the parse API in
/// `backend/api/sorted_api/rrule.py`. Expansion follows the common `rrule`
/// libraries: `DTSTART` is only an occurrence when it matches the rule.
public struct RecurrenceRule: Hashable, Sendable {
    public enum Frequency: String, Sendable, CaseIterable {
        case hourly = "HOURLY"
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    /// Raw values match `Calendar.Component.weekday` (Sunday is 1).
    public enum Weekday: Int, Sendable, CaseIterable, Comparable {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

        public var code: String {
            ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][rawValue - 1]
        }

        public init?(code: String) {
            guard let match = Weekday.allCases.first(where: { $0.code == code }) else { return nil }
            self = match
        }

        public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
            // Monday-first, to match WKST=MO.
            lhs.mondayIndex < rhs.mondayIndex
        }

        var mondayIndex: Int { (rawValue + 5) % 7 }
    }

    /// One `BYDAY` entry: a weekday, optionally with an ordinal (`2TU`, `-1FR`).
    public struct WeekdayNum: Hashable, Sendable {
        public var ordinal: Int?
        public var weekday: Weekday

        public init(_ weekday: Weekday, ordinal: Int? = nil) {
            self.weekday = weekday
            self.ordinal = ordinal
        }

        var code: String { (ordinal.map(String.init) ?? "") + weekday.code }
    }

    public enum Until: Hashable, Sendable {
        /// `UNTIL=20260310T000000Z`: an exact instant.
        case instant(Date)
        /// `UNTIL=20260310`: inclusive through the end of that local day.
        case localDate(year: Int, month: Int, day: Int)
        /// `UNTIL=20260310T180000`: a floating local time.
        case localDateTime(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int)
    }

    public var frequency: Frequency
    public var interval: Int
    public var byDay: [WeekdayNum]
    public var byMonthDay: [Int]
    public var byMonth: [Int]
    public var byHour: [Int]
    public var until: Until?
    public var count: Int?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        byDay: [WeekdayNum] = [],
        byMonthDay: [Int] = [],
        byMonth: [Int] = [],
        byHour: [Int] = [],
        until: Until? = nil,
        count: Int? = nil
    ) throws(RecurrenceRuleError) {
        self.frequency = frequency
        self.interval = interval
        self.byDay = byDay
        self.byMonthDay = byMonthDay
        self.byMonth = byMonth
        self.byHour = byHour
        self.until = until
        self.count = count
        try validate()
    }
}

public enum RecurrenceRuleError: Error, Hashable, Sendable {
    case malformed(String)
    case unsupported(String)
}

// MARK: - Parsing

extension RecurrenceRule {
    /// Parses `FREQ=MONTHLY;BYMONTHDAY=5`, with or without an `RRULE:` prefix.
    public init(_ string: String) throws(RecurrenceRuleError) {
        var body = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.uppercased().hasPrefix("RRULE:") { body.removeFirst(6) }
        guard !body.isEmpty else { throw .malformed("empty rule") }

        var frequency: Frequency?
        var interval = 1
        var byDay: [WeekdayNum] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []
        var byHour: [Int] = []
        var until: Until?
        var count: Int?
        var seen = Set<String>()

        for part in body.split(separator: ";", omittingEmptySubsequences: true) {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { throw .malformed("expected KEY=VALUE, got \(part)") }
            let key = pair[0].uppercased()
            let value = pair[1].uppercased()
            guard seen.insert(key).inserted else { throw .malformed("\(key) appears twice") }

            switch key {
            case "FREQ":
                guard let parsed = Frequency(rawValue: value) else { throw .unsupported("FREQ=\(value)") }
                frequency = parsed
            case "INTERVAL":
                interval = try Self.integer(value, key: key)
            case "COUNT":
                count = try Self.integer(value, key: key)
            case "UNTIL":
                until = try Self.parseUntil(value)
            case "BYDAY":
                byDay = try value.split(separator: ",").map { token throws(RecurrenceRuleError) in
                    try Self.parseWeekdayNum(String(token))
                }
            case "BYMONTHDAY":
                byMonthDay = try Self.integerList(value, key: key)
            case "BYMONTH":
                byMonth = try Self.integerList(value, key: key)
            case "BYHOUR":
                byHour = try Self.integerList(value, key: key)
            case "WKST":
                guard value == "MO" else { throw .unsupported("WKST=\(value)") }
            default:
                throw .unsupported(key)
            }
        }

        guard let frequency else { throw .malformed("FREQ is required") }
        try self.init(
            frequency: frequency, interval: interval, byDay: byDay, byMonthDay: byMonthDay,
            byMonth: byMonth, byHour: byHour, until: until, count: count
        )
    }

    private func validate() throws(RecurrenceRuleError) {
        guard interval >= 1 else { throw .malformed("INTERVAL must be at least 1") }
        if let count, count < 1 { throw .malformed("COUNT must be at least 1") }
        if count != nil, until != nil { throw .malformed("UNTIL and COUNT can't both be set") }
        for day in byMonthDay where day == 0 || !(-31...31).contains(day) {
            throw .malformed("BYMONTHDAY=\(day)")
        }
        for month in byMonth where !(1...12).contains(month) {
            throw .malformed("BYMONTH=\(month)")
        }
        for hour in byHour where !(0...23).contains(hour) {
            throw .malformed("BYHOUR=\(hour)")
        }
        for entry in byDay {
            guard let ordinal = entry.ordinal else { continue }
            guard frequency == .monthly || frequency == .yearly else {
                throw .malformed("BYDAY ordinals need FREQ=MONTHLY or YEARLY")
            }
            guard ordinal != 0, (-5...5).contains(ordinal) else { throw .malformed("BYDAY=\(entry.code)") }
        }
        // "The 20th Monday of the year" style rules: valid RFC 5545, but no
        // household phrase needs them, so refuse rather than guess.
        if frequency == .yearly, !byDay.isEmpty, byMonth.isEmpty {
            throw .unsupported("YEARLY with BYDAY needs BYMONTH")
        }
    }

    private static func integer(_ value: String, key: String) throws(RecurrenceRuleError) -> Int {
        guard let number = Int(value) else { throw .malformed("\(key)=\(value)") }
        return number
    }

    private static func integerList(_ value: String, key: String) throws(RecurrenceRuleError) -> [Int] {
        var numbers: [Int] = []
        for token in value.split(separator: ",") {
            guard let number = Int(token) else { throw .malformed("\(key)=\(value)") }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { throw .malformed("\(key) is empty") }
        return numbers
    }

    private static func parseWeekdayNum(_ token: String) throws(RecurrenceRuleError) -> WeekdayNum {
        guard token.count >= 2, let weekday = Weekday(code: String(token.suffix(2))) else {
            throw .malformed("BYDAY=\(token)")
        }
        let prefix = token.dropLast(2)
        if prefix.isEmpty { return WeekdayNum(weekday) }
        guard let ordinal = Int(prefix) else { throw .malformed("BYDAY=\(token)") }
        return WeekdayNum(weekday, ordinal: ordinal)
    }

    private static func parseUntil(_ value: String) throws(RecurrenceRuleError) -> Until {
        let digits = value.filter(\.isNumber)
        func field(_ offset: Int, _ length: Int) -> Int {
            let start = digits.index(digits.startIndex, offsetBy: offset)
            return Int(digits[start..<digits.index(start, offsetBy: length)])!
        }

        switch value.count {
        case 8 where digits.count == 8:
            return .localDate(year: field(0, 4), month: field(4, 2), day: field(6, 2))
        case 15 where digits.count == 14 && value.dropFirst(8).first == "T",
             16 where digits.count == 14 && value.dropFirst(8).first == "T" && value.hasSuffix("Z"):
            let year = field(0, 4), month = field(4, 2), day = field(6, 2)
            let hour = field(8, 2), minute = field(10, 2), second = field(12, 2)
            guard value.hasSuffix("Z") else {
                return .localDateTime(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            }
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            guard let date = utc.date(from: components) else { throw .malformed("UNTIL=\(value)") }
            return .instant(date)
        default:
            throw .malformed("UNTIL=\(value)")
        }
    }
}

// MARK: - Serializing

extension RecurrenceRule: CustomStringConvertible {
    /// The canonical string form, without the `RRULE:` prefix.
    public var rruleString: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval != 1 { parts.append("INTERVAL=\(interval)") }
        if !byMonth.isEmpty { parts.append("BYMONTH=" + byMonth.map(String.init).joined(separator: ",")) }
        if !byMonthDay.isEmpty { parts.append("BYMONTHDAY=" + byMonthDay.map(String.init).joined(separator: ",")) }
        if !byDay.isEmpty { parts.append("BYDAY=" + byDay.map(\.code).joined(separator: ",")) }
        if !byHour.isEmpty { parts.append("BYHOUR=" + byHour.map(String.init).joined(separator: ",")) }
        if let count { parts.append("COUNT=\(count)") }
        if let until { parts.append("UNTIL=" + until.rruleValue) }
        return parts.joined(separator: ";")
    }

    public var description: String { rruleString }
}

extension RecurrenceRule.Until {
    var rruleValue: String {
        func pad(_ value: Int, _ width: Int) -> String {
            String(repeating: "0", count: max(0, width - String(value).count)) + String(value)
        }
        switch self {
        case let .instant(date):
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            return pad(c.year!, 4) + pad(c.month!, 2) + pad(c.day!, 2) + "T"
                + pad(c.hour!, 2) + pad(c.minute!, 2) + pad(c.second!, 2) + "Z"
        case let .localDate(year, month, day):
            return pad(year, 4) + pad(month, 2) + pad(day, 2)
        case let .localDateTime(year, month, day, hour, minute, second):
            return pad(year, 4) + pad(month, 2) + pad(day, 2) + "T" + pad(hour, 2) + pad(minute, 2) + pad(second, 2)
        }
    }

    /// The last instant an occurrence may fall on, in the given calendar's time zone.
    func lastAllowedDate(in calendar: Calendar) -> Date? {
        switch self {
        case let .instant(date):
            return date
        case let .localDate(year, month, day):
            guard let startOfDay = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)
        case let .localDateTime(year, month, day, hour, minute, second):
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
        }
    }
}
