import Foundation
import SortedKit
import SwiftData

/// One confirmation card: a parsed item the user can edit before saving.
struct CaptureDraft: Identifiable, Equatable {
    let id = UUID()
    var kind: CaptureKind
    var title: String
    var dueDate: Date?
    var allDay: Bool
    var rrule: String?
    var priority: Priority
    var amount: Decimal?
    var currency: String
    var listName: String
    var category: String?
    var question: String?

    init(_ item: ParsedItem, timeZone: TimeZone = .current, listNames: [String]) {
        kind = item.kind
        title = item.title
        dueDate = item.dueAt.flatMap { LocalDateTime.date(from: $0, in: timeZone) }
        allDay = item.allDay
        if allDay, let dueDate {
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            self.dueDate = calendar.startOfDay(for: dueDate)
        }
        rrule = item.rrule.flatMap { (try? RecurrenceRule($0))?.rruleString }
        priority = item.priority
        amount = item.amount
        currency = item.currency ?? Locale.current.currency?.identifier ?? "USD"
        listName = item.listName.flatMap { name in
            listNames.first { $0.localizedCaseInsensitiveCompare(name) == .orderedSame } ?? name
        } ?? listNames.first ?? ShoppingList.defaultNames[0]
        category = item.category
        question = item.needsClarification
    }

    var recurrence: RecurrenceRule? { rrule.flatMap { try? RecurrenceRule($0) } }

    /// "Pay rent · Bill · ₹25,000 · Monthly on the 1st · Reminder 3 days before"
    var summary: String {
        var parts = [title, kind.title]
        switch kind {
        case .bill:
            if let amount { parts.append(amount.formatted(.currency(code: currency))) }
        case .shoppingItem:
            parts.append(listName)
        case .reminder, .task:
            if let dueDate { parts.append(DueFormat.string(for: dueDate, allDay: allDay)) }
        }
        if let recurrence { parts.append(recurrence.summary) }
        if kind == .bill { parts.append("Reminder 3 days before") }
        return parts.joined(separator: " · ")
    }

    /// Writes the draft to the store. Returns true when it needs notifications.
    @MainActor
    @discardableResult
    func save(in context: ModelContext, lists: [ShoppingList]) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        // All-day items are stored at the start of their day.
        let dueDate = allDay ? dueDate.map(Calendar.current.startOfDay(for:)) : dueDate

        switch kind {
        case .reminder, .task:
            let task = TaskItem(
                title: title, dueAt: dueDate, allDay: allDay, rrule: dueDate == nil ? nil : rrule,
                priority: priority, remind: dueDate != nil
            )
            context.insert(task)
            return task.remind
        case .bill:
            let bill = Bill(name: title, amount: amount, currency: currency, rrule: rrule, nextDueOn: dueDate ?? .now)
            context.insert(bill)
            return true
        case .shoppingItem:
            let list = lists.first { $0.name.localizedCaseInsensitiveCompare(listName) == .orderedSame } ?? {
                let list = ShoppingList(name: listName, sortOrder: lists.count)
                context.insert(list)
                return list
            }()
            list.add(title, category: category)
            return false
        }
    }
}

enum DueFormat {
    /// "Today, 6:00 PM", "Tomorrow", "Fri, Nov 13, 9:00 AM".
    static func string(for date: Date, allDay: Bool, now: Date = .now) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            day = "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        } else {
            day = date.formatted(date: .abbreviated, time: .omitted)
        }
        return allDay ? day : "\(day), \(date.formatted(date: .omitted, time: .shortened))"
    }
}
