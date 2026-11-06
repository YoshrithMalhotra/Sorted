import Foundation
import Testing
@testable import SortedKit

@Suite("Current occurrence")
struct OccurrencesTests {
    let daily = try! RecurrenceRule("FREQ=DAILY")
    let start = local("2026-11-01T09:00")

    @Test func oneOffTaskIsItsStartUntilCompleted() {
        #expect(Occurrences.current(rule: nil, start: start, in: kolkata, completed: [], now: local("2026-11-06T10:00")) == start)
        #expect(Occurrences.current(rule: nil, start: start, in: kolkata, completed: [start], now: local("2026-11-06T10:00")) == nil)
    }

    @Test func missedOccurrencesCollapseIntoTheLatest() {
        let current = Occurrences.current(rule: daily, start: start, in: kolkata, completed: [], now: local("2026-11-06T10:00"))
        #expect(current == local("2026-11-06T09:00"))
    }

    @Test func completingMovesToTheNextFutureOccurrence() {
        let current = Occurrences.current(
            rule: daily, start: start, in: kolkata,
            completed: [local("2026-11-06T09:00")], now: local("2026-11-06T10:00")
        )
        #expect(current == local("2026-11-07T09:00"))
    }

    @Test func beforeTheFirstOccurrenceItIsTheStart() {
        let current = Occurrences.current(rule: daily, start: start, in: kolkata, completed: [], now: local("2026-10-20T10:00"))
        #expect(current == start)
    }

    @Test func finishedRuleHasNothingLeft() throws {
        let twice = try RecurrenceRule("FREQ=DAILY;COUNT=2")
        let completed: Set = [local("2026-11-01T09:00"), local("2026-11-02T09:00")]
        #expect(Occurrences.current(rule: twice, start: start, in: kolkata, completed: completed, now: local("2026-11-06T10:00")) == nil)
    }
}

@Suite("Notification planner")
struct NotificationPlannerTests {
    let now = local("2026-11-06T10:00")
    let planner = NotificationPlanner(timeZone: kolkata, defaultTime: TimeOfDay(hour: 9))

    func reminder(_ rule: String?, start: String, allDay: Bool = false, completed: Set<Date> = [], snoozedUntil: Date? = nil) -> ReminderSource {
        ReminderSource(
            id: UUID(), title: "Water plants", start: local(start), allDay: allDay,
            rule: rule.map { try! RecurrenceRule($0) }, completedOccurrences: completed, snoozedUntil: snoozedUntil
        )
    }

    @Test func dailyReminderFillsTheFourteenDayWindow() {
        let plan = planner.plan(reminders: [reminder("FREQ=DAILY", start: "2026-11-01T18:00")], bills: [], now: now)
        #expect(plan.count == 14)
        #expect(localStrings(plan.map(\.fireDate)).first == "2026-11-06T18:00")
        #expect(localStrings(plan.map(\.fireDate)).last == "2026-11-19T18:00")
        #expect(plan.allSatisfy { $0.category == .task })
    }

    @Test func skipsPastAndCompletedOccurrences() {
        let task = reminder("FREQ=DAILY", start: "2026-11-01T18:00", completed: [local("2026-11-06T18:00")])
        let plan = planner.plan(reminders: [task], bills: [], now: now)
        #expect(localStrings(plan.map(\.fireDate)).first == "2026-11-07T18:00")
    }

    @Test func allDayTaskFiresAtTheDefaultTime() {
        let task = reminder(nil, start: "2026-11-08T00:00", allDay: true)
        let plan = planner.plan(reminders: [task], bills: [], now: now)
        #expect(localStrings(plan.map(\.fireDate)) == ["2026-11-08T09:00"])
        #expect(plan.first?.occurrence == local("2026-11-08T00:00"))
    }

    @Test func snoozeReplacesEarlierAlerts() {
        let task = reminder("FREQ=HOURLY", start: "2026-11-06T09:30", snoozedUntil: local("2026-11-06T13:00"))
        let fires = localStrings(planner.plan(reminders: [task], bills: [], now: now).map(\.fireDate))
        #expect(fires.prefix(3) == ["2026-11-06T13:00", "2026-11-06T13:30", "2026-11-06T14:30"])
    }

    @Test func billGetsPreAlertAndDueDayAlert() {
        let bill = BillSource(
            id: UUID(), name: "Rent", amount: 25_000, currency: "INR", nextDue: local("2026-12-01T00:00"),
            rule: try! RecurrenceRule("FREQ=MONTHLY;BYMONTHDAY=1")
        )
        let plan = planner.plan(reminders: [], bills: [bill], now: local("2026-11-25T10:00"))
        #expect(localStrings(plan.map(\.fireDate)) == ["2026-11-28T09:00", "2026-12-01T09:00"])
        #expect(plan.map(\.title) == ["Rent is due in 3 days", "Rent is due today"])
        #expect(plan.allSatisfy { $0.occurrence == local("2026-12-01T00:00") })
    }

    @Test func preAlertForADueDateJustPastTheWindow() {
        // Due Nov 21 at the earliest: the due-day alert is past the 14-day
        // window, but its pre-alert on Nov 18 is inside it.
        let bill = BillSource(id: UUID(), name: "Phone", amount: nil, currency: "INR", nextDue: local("2026-11-21T00:00"), rule: nil)
        let plan = planner.plan(reminders: [], bills: [bill], now: now)
        #expect(localStrings(plan.map(\.fireDate)) == ["2026-11-18T09:00"])
    }

    @Test func paidDueDatesAreSkipped() {
        let due = local("2026-11-10T00:00")
        let bill = BillSource(id: UUID(), name: "Gym", amount: 1500, currency: "INR", nextDue: due, rule: nil, paidDueDates: [due])
        #expect(planner.plan(reminders: [], bills: [bill], now: now).isEmpty)
    }

    @Test func overflowKeepsSixtyAndAddsANotice() {
        let busy = reminder("FREQ=HOURLY", start: "2026-11-06T10:30")
        let plan = planner.plan(reminders: [busy], bills: [], now: now)
        #expect(plan.count == 61)
        #expect(plan.last?.category == .overflow)
        #expect(plan.last!.fireDate > plan[59].fireDate)
        #expect(plan.count <= 64)
    }

    @Test func identifiersAreUnique() {
        let tasks = (0..<5).map { _ in reminder("FREQ=DAILY", start: "2026-11-01T18:00") }
        let plan = planner.plan(reminders: tasks, bills: [], now: now)
        #expect(Set(plan.map(\.identifier)).count == plan.count)
    }
}

@Suite("Snooze")
struct SnoozeTests {
    @Test func options() {
        let now = local("2026-11-06T10:00")
        let time = TimeOfDay(hour: 9)
        #expect(SnoozeOption.oneHour.wakeDate(now: now, in: kolkata, defaultTime: time) == local("2026-11-06T11:00"))
        #expect(SnoozeOption.tonight.wakeDate(now: now, in: kolkata, defaultTime: time) == local("2026-11-06T20:00"))
        #expect(SnoozeOption.tomorrow.wakeDate(now: now, in: kolkata, defaultTime: time) == local("2026-11-07T09:00"))
        #expect(SnoozeOption.tonight.wakeDate(now: local("2026-11-06T21:00"), in: kolkata, defaultTime: time) == nil)
    }
}
