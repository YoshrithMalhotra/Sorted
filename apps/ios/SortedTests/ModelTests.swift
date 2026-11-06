import Foundation
import SortedKit
import SwiftData
import Testing
@testable import Sorted

@MainActor
@Suite("Models")
struct ModelTests {
    // Held so the store outlives init: a context doesn't retain its container.
    let container: ModelContainer
    let context: ModelContext
    let calendar = Calendar.current

    init() throws {
        container = try ModelContainer(
            for: TaskItem.self, Bill.self, ShoppingList.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func completingARecurringTaskMovesToTheNextOccurrence() {
        let task = TaskItem(title: "Water plants", dueAt: date(1, 9), rrule: "FREQ=DAILY", remind: true)
        context.insert(task)
        let now = date(6, 10)
        #expect(task.currentOccurrence(now: now) == date(6, 9))

        task.complete(now: now)
        #expect(task.completedAt == nil)
        #expect(task.currentOccurrence(now: now) == date(7, 9))
    }

    @Test func completingAOneOffTaskFinishesIt() {
        let task = TaskItem(title: "Renew insurance", dueAt: date(6, 9))
        context.insert(task)
        task.complete(now: date(6, 10))
        #expect(task.completedAt != nil)
        #expect(task.currentOccurrence(now: date(6, 10)) == nil)
        #expect(task.reminderSource() == nil)
    }

    @Test func agendaGroupsAndSorts() {
        let now = date(6, 12)
        let overdue = TaskItem(title: "Overdue", dueAt: date(5, 9))
        let allDayToday = TaskItem(title: "All day today", dueAt: date(6), allDay: true)
        let laterToday = TaskItem(title: "Later", dueAt: date(6, 18))
        let urgentToday = TaskItem(title: "Urgent", dueAt: date(6, 20), priority: .high)
        let nextWeek = TaskItem(title: "Next week", dueAt: date(10, 9))
        let farAway = TaskItem(title: "Far away", dueAt: date(30, 9))
        let undated = TaskItem(title: "Someday")
        for task in [overdue, allDayToday, laterToday, urgentToday, nextWeek, farAway, undated] { context.insert(task) }

        let agenda = Agenda(tasks: [overdue, allDayToday, laterToday, urgentToday, nextWeek, farAway, undated], now: now)
        #expect(agenda.overdue.map(\.task.title) == ["Overdue"])
        #expect(agenda.today.map(\.task.title) == ["Urgent", "All day today", "Later"])
        #expect(agenda.upcoming.map(\.task.title) == ["Next week"])
        #expect(agenda.someday.map(\.task.title) == ["Someday"])
    }

    @Test func snoozedTaskMovesToItsWakeTime() {
        let task = TaskItem(title: "Call bank", dueAt: date(6, 9))
        context.insert(task)
        task.snooze(until: date(7, 9))
        let agenda = Agenda(tasks: [task], now: date(6, 12))
        #expect(agenda.overdue.isEmpty)
        #expect(agenda.upcoming.first?.effectiveDate == date(7, 9))
    }

    @Test func markingABillPaidAdvancesItsDueDate() {
        let bill = Bill(name: "Rent", amount: 25_000, currency: "INR", rrule: "FREQ=MONTHLY;BYMONTHDAY=1", nextDueOn: date(1))
        context.insert(bill)
        let now = date(6, 12)
        let end = calendar.date(byAdding: .day, value: 30, to: date(6))!

        // Nov 1 is overdue and Dec 1 is inside the 30 days.
        #expect(bill.unpaidDueDates(before: end, now: now) == [date(1), calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!])

        bill.markPaid(dueOn: date(1), now: now)
        #expect(bill.nextDueOn == calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        #expect(bill.payments.count == 1)
    }

    @Test func autopayBillsNeverShowOverdue() {
        let bill = Bill(name: "Netflix", amount: 649, currency: "INR", rrule: "FREQ=MONTHLY", nextDueOn: date(1), autopay: true)
        context.insert(bill)
        let end = calendar.date(byAdding: .day, value: 30, to: date(6))!
        #expect(bill.unpaidDueDates(before: end, now: date(6, 12)) == [calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!])
    }

    @Test func savingDraftsCreatesTheRightRows() throws {
        let groceries = ShoppingList(name: "Groceries", sortOrder: 0)
        context.insert(groceries)
        let items = [
            ParsedItem(kind: .shoppingItem, title: "Milk", listName: "groceries", category: "Dairy"),
            ParsedItem(kind: .shoppingItem, title: "Paracetamol", listName: "Pharmacy"),
            ParsedItem(kind: .bill, title: "Rent", dueAt: "2026-12-01T00:00:00", allDay: true, rrule: "FREQ=MONTHLY;BYMONTHDAY=1", amount: 25_000, currency: "INR"),
            ParsedItem(kind: .reminder, title: "Call mom", dueAt: "2026-11-08T18:00:00", rrule: "FREQ=WEEKLY"),
        ]
        for item in items {
            CaptureDraft(item, listNames: ["Groceries"]).save(in: context, lists: [groceries])
        }

        #expect(groceries.items.map(\.name) == ["Milk"])
        let lists = try context.fetch(FetchDescriptor<ShoppingList>())
        #expect(Set(lists.map(\.name)) == ["Groceries", "Pharmacy"])
        let bill = try #require(try context.fetch(FetchDescriptor<Bill>()).first)
        #expect(bill.amount == 25_000)
        #expect(bill.nextDueOn == calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(task.remind)
        #expect(task.rrule == "FREQ=WEEKLY")
    }
}
