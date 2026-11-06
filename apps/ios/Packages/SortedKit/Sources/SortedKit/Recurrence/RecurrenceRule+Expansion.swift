import Foundation

extension RecurrenceRule {
    /// Upper bound on periods walked in one expansion, so a rule that can never
    /// match (`FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30`) can't loop forever.
    static let maxPeriods = 200_000

    /// Occurrences of the rule that start at `start`, falling in `lower..<upper`.
    ///
    /// Times of day are kept in local time, so "9 AM every day" stays 9 AM
    /// across daylight-saving changes. `COUNT` counts from `start`, not from
    /// `lower`.
    public func occurrences(
        startingAt start: Date,
        in timeZone: TimeZone,
        from lower: Date,
        to upper: Date,
        limit: Int = .max
    ) -> [Date] {
        guard lower < upper, limit > 0 else { return [] }
        let expander = Expander(rule: self, start: start, timeZone: timeZone)
        let lastAllowed = until?.lastAllowedDate(in: expander.calendar)

        var results: [Date] = []
        var produced = 0
        // Without COUNT the earlier periods can't affect the result, so jump
        // straight to the period that contains `lower`.
        var index = count == nil ? expander.periodIndex(containing: lower) : 0

        for _ in 0..<Self.maxPeriods {
            guard let periodStart = expander.periodStart(index) else { break }
            if periodStart >= upper { break }
            if let lastAllowed, periodStart > lastAllowed { break }

            for candidate in expander.candidates(inPeriod: index) where candidate >= start {
                if let lastAllowed, candidate > lastAllowed { return results }
                produced += 1
                if let count, produced > count { return results }
                if candidate >= upper { return results }
                if candidate >= lower {
                    results.append(candidate)
                    if results.count >= limit { return results }
                }
            }
            index += 1
        }
        return results
    }

    /// The first occurrence strictly after `date`, looking up to ten years ahead.
    public func nextOccurrence(after date: Date, startingAt start: Date, in timeZone: TimeZone) -> Date? {
        let lower = date.addingTimeInterval(1)
        let upper = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: lower)!
        return occurrences(startingAt: start, in: timeZone, from: lower, to: upper, limit: 1).first
    }
}

/// Walks a rule period by period: one hour, day, week, month or year at a
/// time, stepping by `INTERVAL`, and lists the occurrences in each period.
private struct Expander {
    let rule: RecurrenceRule
    let start: Date
    let calendar: Calendar
    /// `start` broken into local components.
    let origin: DateComponents
    /// Start of the period that contains `start`.
    let anchor: Date

    init(rule: RecurrenceRule, start: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // WKST=MO
        self.rule = rule
        self.start = start
        self.calendar = calendar
        self.origin = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: start)

        switch rule.frequency {
        case .hourly:
            anchor = calendar.dateInterval(of: .hour, for: start)!.start
        case .daily:
            anchor = calendar.startOfDay(for: start)
        case .weekly:
            anchor = calendar.dateInterval(of: .weekOfYear, for: start)!.start
        case .monthly:
            anchor = calendar.date(from: DateComponents(year: origin.year, month: origin.month, day: 1))!
        case .yearly:
            anchor = calendar.date(from: DateComponents(year: origin.year, month: 1, day: 1))!
        }
    }

    private var unit: Calendar.Component {
        switch rule.frequency {
        case .hourly: .hour
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }

    func periodStart(_ index: Int) -> Date? {
        let steps = index * rule.interval
        if rule.frequency == .hourly {
            // Absolute hours: local "hours" repeat or vanish around DST changes.
            return anchor.addingTimeInterval(TimeInterval(steps) * 3600)
        }
        return calendar.date(byAdding: unit, value: steps, to: anchor)
    }

    /// The index of a period at or just before the one containing `date`.
    func periodIndex(containing date: Date) -> Int {
        guard date > anchor else { return 0 }
        let units: Int
        switch rule.frequency {
        case .hourly:
            units = Int(date.timeIntervalSince(anchor) / 3600)
        case .daily:
            units = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
        case .weekly:
            units = (calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0) / 7
        case .monthly:
            let c = calendar.dateComponents([.year, .month], from: date)
            units = (c.year! - origin.year!) * 12 + (c.month! - origin.month!)
        case .yearly:
            units = calendar.component(.year, from: date) - origin.year!
        }
        // One period of slack in case a calendar quirk rounds the count up.
        return max(0, units / rule.interval - 1)
    }

    /// Every occurrence in the period, sorted. May include dates before `start`.
    func candidates(inPeriod index: Int) -> [Date] {
        guard let periodStart = periodStart(index) else { return [] }
        switch rule.frequency {
        case .hourly:
            let local = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: periodStart)
            guard rule.byHour.isEmpty || rule.byHour.contains(local.hour!),
                  dayMatchesFilters(local) else { return [] }
            return [periodStart.addingTimeInterval(TimeInterval(origin.minute! * 60 + origin.second!))]

        case .daily:
            let local = calendar.dateComponents([.year, .month, .day, .weekday], from: periodStart)
            guard dayMatchesFilters(local) else { return [] }
            return times(onYear: local.year!, month: local.month!, day: local.day!)

        case .weekly:
            let weekdays = rule.byDay.isEmpty
                ? [RecurrenceRule.Weekday(rawValue: origin.weekday!)!]
                : rule.byDay.map(\.weekday)
            var dates: [Date] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: periodStart) else { continue }
                let local = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
                guard weekdays.contains(where: { $0.rawValue == local.weekday! }),
                      rule.byMonth.isEmpty || rule.byMonth.contains(local.month!) else { continue }
                dates += times(onYear: local.year!, month: local.month!, day: local.day!)
            }
            return dates.sorted()

        case .monthly:
            let local = calendar.dateComponents([.year, .month], from: periodStart)
            guard rule.byMonth.isEmpty || rule.byMonth.contains(local.month!) else { return [] }
            return daysInMonth(year: local.year!, month: local.month!)
                .flatMap { times(onYear: local.year!, month: local.month!, day: $0) }

        case .yearly:
            let year = calendar.component(.year, from: periodStart)
            let months = rule.byMonth.isEmpty ? [origin.month!] : rule.byMonth.sorted()
            return months.flatMap { month in
                daysInMonth(year: year, month: month).flatMap { times(onYear: year, month: month, day: $0) }
            }
        }
    }

    /// BYMONTH, BYMONTHDAY and BYDAY used as filters, for HOURLY and DAILY.
    private func dayMatchesFilters(_ local: DateComponents) -> Bool {
        if !rule.byMonth.isEmpty, !rule.byMonth.contains(local.month!) { return false }
        if !rule.byDay.isEmpty, !rule.byDay.contains(where: { $0.weekday.rawValue == local.weekday! }) { return false }
        if !rule.byMonthDay.isEmpty {
            let length = monthLength(year: local.year!, month: local.month!)
            let day = local.day!
            if !rule.byMonthDay.contains(where: { $0 == day || length + $0 + 1 == day }) { return false }
        }
        return true
    }

    /// The days of one month that the rule selects, sorted. Without BYMONTHDAY
    /// or BYDAY it is the start's day of month, which short months skip.
    private func daysInMonth(year: Int, month: Int) -> [Int] {
        let length = monthLength(year: year, month: month)

        let monthDays: Set<Int>? = rule.byMonthDay.isEmpty ? nil : Set(rule.byMonthDay.compactMap { value in
            let day = value > 0 ? value : length + value + 1
            return (1...length).contains(day) ? day : nil
        })

        var weekDays: Set<Int>?
        if !rule.byDay.isEmpty {
            let firstWeekday = calendar.component(.weekday, from: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)
            var selected = Set<Int>()
            for entry in rule.byDay {
                let firstMatch = (entry.weekday.rawValue - firstWeekday + 7) % 7 + 1
                let matches = Array(stride(from: firstMatch, through: length, by: 7))
                switch entry.ordinal {
                case nil:
                    selected.formUnion(matches)
                case let ordinal? where ordinal > 0 && ordinal <= matches.count:
                    selected.insert(matches[ordinal - 1])
                case let ordinal? where ordinal < 0 && -ordinal <= matches.count:
                    selected.insert(matches[matches.count + ordinal])
                default:
                    break
                }
            }
            weekDays = selected
        }

        switch (monthDays, weekDays) {
        case let (monthDays?, weekDays?): return monthDays.intersection(weekDays).sorted()
        case let (monthDays?, nil): return monthDays.sorted()
        case let (nil, weekDays?): return weekDays.sorted()
        case (nil, nil): return origin.day! <= length ? [origin.day!] : []
        }
    }

    /// The occurrence times on one local day: each BYHOUR, or the start's hour,
    /// at the start's minute and second.
    private func times(onYear year: Int, month: Int, day: Int) -> [Date] {
        let hours = rule.byHour.isEmpty ? [origin.hour!] : rule.byHour.sorted()
        return hours.compactMap { hour in
            calendar.date(from: DateComponents(
                year: year, month: month, day: day,
                hour: hour, minute: origin.minute, second: origin.second
            ))
        }
    }

    private func monthLength(year: Int, month: Int) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return calendar.range(of: .day, in: .month, for: first)!.count
    }
}
