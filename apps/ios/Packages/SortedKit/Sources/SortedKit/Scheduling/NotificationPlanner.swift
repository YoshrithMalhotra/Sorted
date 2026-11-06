import Foundation

/// A task or reminder the planner may notify about (`tasks.remind = true`).
public struct ReminderSource: Sendable {
    public var id: UUID
    public var title: String
    public var notes: String?
    /// The first occurrence. For an all-day task, the start of that local day.
    public var start: Date
    public var allDay: Bool
    public var rule: RecurrenceRule?
    public var completedOccurrences: Set<Date>
    public var snoozedUntil: Date?

    public init(
        id: UUID, title: String, notes: String? = nil, start: Date, allDay: Bool,
        rule: RecurrenceRule?, completedOccurrences: Set<Date> = [], snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.start = start
        self.allDay = allDay
        self.rule = rule
        self.completedOccurrences = completedOccurrences
        self.snoozedUntil = snoozedUntil
    }
}

/// A bill or subscription the planner may notify about.
public struct BillSource: Sendable {
    public var id: UUID
    public var name: String
    public var amount: Decimal?
    public var currency: String
    /// The next due date, at the start of that local day.
    public var nextDue: Date
    public var rule: RecurrenceRule?
    public var remindDaysBefore: Int
    public var autopay: Bool
    /// Due dates already marked paid (`bill_payments.due_on`).
    public var paidDueDates: Set<Date>
    public var snoozedUntil: Date?

    public init(
        id: UUID, name: String, amount: Decimal?, currency: String, nextDue: Date,
        rule: RecurrenceRule?, remindDaysBefore: Int = 3, autopay: Bool = false,
        paidDueDates: Set<Date> = [], snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currency = currency
        self.nextDue = nextDue
        self.rule = rule
        self.remindDaysBefore = remindDaysBefore
        self.autopay = autopay
        self.paidDueDates = paidDueDates
        self.snoozedUntil = snoozedUntil
    }
}

public struct PlannedNotification: Hashable, Sendable {
    public enum Category: String, Sendable {
        /// Actions: Done, Snooze 1 h.
        case task = "TASK"
        /// Actions: Mark paid, Remind me tomorrow.
        case bill = "BILL"
        /// "You have more reminders — open the app".
        case overflow = "OVERFLOW"
    }

    public enum Variant: String, Sendable {
        case due, preAlert = "pre", snoozed, overflow
    }

    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var category: Category
    public var variant: Variant
    public var itemID: UUID?
    /// The occurrence the notification is about: what Done or Mark paid acts on.
    public var occurrence: Date?
}

/// Picks which local notifications to keep pending.
///
/// iOS keeps at most 64 pending local notifications per app, so the planner
/// expands every rule over the next 14 days, sorts by fire time and keeps the
/// soonest 60. If anything was cut, one more notification after the last one
/// asks the user to open the app, which schedules the next window.
public struct NotificationPlanner: Sendable {
    public var windowDays = 14
    public var capacity = 60
    public var timeZone: TimeZone
    public var defaultTime: TimeOfDay

    public init(timeZone: TimeZone, defaultTime: TimeOfDay = .defaultReminder) {
        self.timeZone = timeZone
        self.defaultTime = defaultTime
    }

    public func plan(reminders: [ReminderSource], bills: [BillSource], now: Date) -> [PlannedNotification] {
        let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: now)!
        var candidates = reminders.flatMap { notifications(for: $0, now: now, until: windowEnd) }
            + bills.flatMap { notifications(for: $0, now: now, until: windowEnd) }
        candidates.sort { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }

        guard candidates.count > capacity else { return candidates }
        var kept = Array(candidates.prefix(capacity))
        let noticeDate = kept.last!.fireDate.addingTimeInterval(60)
        kept.append(PlannedNotification(
            identifier: "overflow",
            fireDate: noticeDate,
            title: "You have more reminders",
            body: "Open Sorted to keep them coming.",
            category: .overflow,
            variant: .overflow
        ))
        return kept
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func fireDate(forOccurrence occurrence: Date, allDay: Bool) -> Date {
        allDay ? defaultTime.on(occurrence, in: timeZone) : occurrence
    }

    private func notifications(for task: ReminderSource, now: Date, until windowEnd: Date) -> [PlannedNotification] {
        // An all-day occurrence fires later than it starts, so look back a day.
        let lower = task.allDay ? calendar.date(byAdding: .day, value: -1, to: now)! : now
        let occurrences: [Date]
        if let rule = task.rule {
            occurrences = rule.occurrences(startingAt: task.start, in: timeZone, from: lower, to: windowEnd)
        } else {
            occurrences = task.completedOccurrences.isEmpty ? [task.start] : []
        }

        let snoozedUntil = task.snoozedUntil.flatMap { $0 > now ? $0 : nil }
        var results: [PlannedNotification] = []
        for occurrence in occurrences where !task.completedOccurrences.contains(occurrence) {
            let fire = fireDate(forOccurrence: occurrence, allDay: task.allDay)
            // A snooze replaces every alert that would have fired before it.
            guard fire > now, fire < windowEnd, snoozedUntil.map({ fire >= $0 }) ?? true else { continue }
            results.append(taskNotification(task, occurrence: occurrence, fire: fire, variant: .due))
        }

        if let snoozedUntil, snoozedUntil < windowEnd,
           let occurrence = Occurrences.current(
               rule: task.rule, start: task.start, in: timeZone,
               completed: task.completedOccurrences, now: now
           ) {
            results.append(taskNotification(task, occurrence: occurrence, fire: snoozedUntil, variant: .snoozed))
        }
        return results
    }

    private func taskNotification(
        _ task: ReminderSource, occurrence: Date, fire: Date, variant: PlannedNotification.Variant
    ) -> PlannedNotification {
        PlannedNotification(
            identifier: Self.identifier("task", task.id, occurrence, variant),
            fireDate: fire,
            title: task.title,
            body: task.notes ?? "",
            category: .task,
            variant: variant,
            itemID: task.id,
            occurrence: occurrence
        )
    }

    private func notifications(for bill: BillSource, now: Date, until windowEnd: Date) -> [PlannedNotification] {
        // A pre-alert inside the window can belong to a due date past its end.
        let lookAhead = calendar.date(byAdding: .day, value: bill.remindDaysBefore, to: windowEnd)!
        let lower = calendar.date(byAdding: .day, value: -1, to: now)!
        let dueDates: [Date]
        if let rule = bill.rule {
            dueDates = rule.occurrences(startingAt: bill.nextDue, in: timeZone, from: lower, to: lookAhead)
        } else {
            dueDates = bill.nextDue >= lower ? [bill.nextDue] : []
        }

        let snoozedUntil = bill.snoozedUntil.flatMap { $0 > now ? $0 : nil }
        var results: [PlannedNotification] = []
        for due in dueDates where !bill.paidDueDates.contains(due) {
            var alerts: [(PlannedNotification.Variant, Date)] = [(.due, defaultTime.on(due, in: timeZone))]
            if bill.remindDaysBefore > 0, let early = calendar.date(byAdding: .day, value: -bill.remindDaysBefore, to: due) {
                alerts.append((.preAlert, defaultTime.on(early, in: timeZone)))
            }
            for (variant, fire) in alerts {
                guard fire > now, fire < windowEnd, snoozedUntil.map({ fire >= $0 }) ?? true else { continue }
                results.append(billNotification(bill, due: due, fire: fire, variant: variant))
            }
        }

        if let snoozedUntil, snoozedUntil < windowEnd,
           let due = dueDates.first(where: { !bill.paidDueDates.contains($0) }) {
            results.append(billNotification(bill, due: due, fire: snoozedUntil, variant: .snoozed))
        }
        return results
    }

    private func billNotification(
        _ bill: BillSource, due: Date, fire: Date, variant: PlannedNotification.Variant
    ) -> PlannedNotification {
        let title: String
        switch variant {
        case .preAlert:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: fire), to: due).day ?? bill.remindDaysBefore
            title = days == 1 ? "\(bill.name) is due tomorrow" : "\(bill.name) is due in \(days) days"
        default:
            title = calendar.isDate(fire, inSameDayAs: due) ? "\(bill.name) is due today" : "\(bill.name) is due"
        }

        var details: [String] = []
        if let amount = bill.amount {
            details.append(amount.formatted(.currency(code: bill.currency)))
        }
        if bill.autopay { details.append("Autopay is on") }

        return PlannedNotification(
            identifier: Self.identifier("bill", bill.id, due, variant),
            fireDate: fire,
            title: title,
            body: details.joined(separator: " · "),
            category: .bill,
            variant: variant,
            itemID: bill.id,
            occurrence: due
        )
    }

    static func identifier(_ kind: String, _ id: UUID, _ occurrence: Date, _ variant: PlannedNotification.Variant) -> String {
        "\(kind).\(id.uuidString).\(Int(occurrence.timeIntervalSince1970)).\(variant.rawValue)"
    }
}
