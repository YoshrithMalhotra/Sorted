import Foundation
import SortedKit
import SwiftData

/// A row of `bills`: a bill or subscription. Never holds card or account numbers.
@Model
final class Bill {
    @Attribute(.unique) var id: UUID
    var householdID: UUID?
    var name: String
    var amount: Decimal?
    /// ISO 4217 code.
    var currency: String
    var rrule: String?
    /// The start of the local day the next unpaid payment is due.
    var nextDueOn: Date
    var category: String?
    var autopay: Bool
    var remindDaysBefore: Int
    /// Set by the "Remind me tomorrow" notification action. Local only for now:
    /// `bills` needs a `snoozed_until` column before this syncs.
    var snoozedUntil: Date?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BillPayment.bill)
    var payments: [BillPayment] = []

    init(
        name: String, amount: Decimal? = nil, currency: String = Locale.current.currency?.identifier ?? "USD",
        rrule: String? = nil, nextDueOn: Date, category: String? = nil, autopay: Bool = false,
        remindDaysBefore: Int = 3
    ) {
        id = UUID()
        self.name = name
        self.amount = amount
        self.currency = currency
        self.rrule = rrule
        self.nextDueOn = Calendar.current.startOfDay(for: nextDueOn)
        self.category = category
        self.autopay = autopay
        self.remindDaysBefore = remindDaysBefore
        createdAt = .now
        updatedAt = .now
    }

    var recurrence: RecurrenceRule? {
        rrule.flatMap { try? RecurrenceRule($0) }
    }

    var paidDueDates: Set<Date> {
        Set(payments.map(\.dueOn))
    }

    /// Unpaid due dates before `end`, including overdue ones. Autopay bills
    /// pay themselves, so their past due dates never show as overdue.
    func unpaidDueDates(before end: Date, now: Date = .now, in timeZone: TimeZone = .current) -> [Date] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let lower = autopay ? max(today, nextDueOn) : nextDueOn
        let paid = paidDueDates

        guard let rule = recurrence else {
            return nextDueOn >= lower && nextDueOn < end && !paid.contains(nextDueOn) ? [nextDueOn] : []
        }
        return rule.occurrences(startingAt: nextDueOn, in: timeZone, from: lower, to: end)
            .filter { !paid.contains($0) }
    }

    /// Records a payment and moves `nextDueOn` to the earliest unpaid due date.
    func markPaid(dueOn: Date, now: Date = .now, in timeZone: TimeZone = .current) {
        payments.append(BillPayment(dueOn: dueOn, paidOn: now, amountPaid: amount))
        if let rule = recurrence {
            let paid = paidDueDates
            while paid.contains(nextDueOn),
                  let next = rule.nextOccurrence(after: nextDueOn, startingAt: nextDueOn, in: timeZone) {
                nextDueOn = next
            }
        }
        snoozedUntil = nil
        updatedAt = now
    }

    func billSource() -> BillSource {
        BillSource(
            id: id, name: name, amount: amount, currency: currency, nextDue: nextDueOn, rule: recurrence,
            remindDaysBefore: remindDaysBefore, autopay: autopay, paidDueDates: paidDueDates,
            snoozedUntil: snoozedUntil
        )
    }
}

/// A row of `bill_payments`: the "mark paid" history.
@Model
final class BillPayment {
    var dueOn: Date
    var paidOn: Date
    var amountPaid: Decimal?
    var bill: Bill?

    init(dueOn: Date, paidOn: Date, amountPaid: Decimal?) {
        self.dueOn = dueOn
        self.paidOn = paidOn
        self.amountPaid = amountPaid
    }
}
