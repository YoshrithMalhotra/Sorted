import Foundation
import SwiftData

/// An in-memory store with sample data, for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: TaskItem.self, Bill.self, ShoppingList.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, hour: Int? = nil) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return hour.map { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: date)! } ?? date
        }

        context.insert(TaskItem(title: "Call Mom", dueAt: day(0, hour: 19), rrule: "FREQ=WEEKLY", remind: true))
        context.insert(TaskItem(title: "Renew car insurance", dueAt: day(-1), allDay: true, priority: .high, remind: true))
        context.insert(TaskItem(title: "Water the plants", dueAt: day(2, hour: 8), rrule: "FREQ=DAILY;INTERVAL=3", remind: true))
        context.insert(TaskItem(title: "Book dentist appointment"))

        context.insert(Bill(name: "Rent", amount: 25_000, currency: "INR", rrule: "FREQ=MONTHLY;BYMONTHDAY=1", nextDueOn: day(5)))
        context.insert(Bill(name: "Electricity", amount: 1_840, currency: "INR", rrule: "FREQ=MONTHLY;BYMONTHDAY=5", nextDueOn: day(9)))
        context.insert(Bill(name: "Netflix", amount: 649, currency: "INR", rrule: "FREQ=MONTHLY", nextDueOn: day(12), autopay: true))

        let groceries = ShoppingList(name: "Groceries", sortOrder: 0)
        context.insert(groceries)
        for name in ["Milk", "Eggs", "Dish soap", "Bananas", "Bread"] { groceries.add(name) }
        context.insert(ShoppingList(name: "Pharmacy", sortOrder: 1))
        return container
    }()
}
