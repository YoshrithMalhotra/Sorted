import BackgroundTasks
import Foundation
import OSLog
import SortedKit
import SwiftData
import UserNotifications

/// Keeps the pending local notifications in step with the data.
///
/// Call `reschedule()` when the app opens, after any create, edit or complete,
/// and from the background refresh task. Each call replaces everything
/// pending with the planner's soonest 60 alerts.
@MainActor
final class ReminderScheduler {
    nonisolated static let refreshTaskID = "app.sorted.refresh"

    private let container: ModelContainer
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "app.sorted", category: "notifications")

    init(container: ModelContainer) {
        self.container = container
    }

    func reschedule(now: Date = .now) async {
        let context = container.mainContext
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.remind && $0.completedAt == nil }))) ?? []
        let bills = (try? context.fetch(FetchDescriptor<Bill>())) ?? []

        let planner = NotificationPlanner(timeZone: .current, defaultTime: AppSettings.defaultReminderTime)
        let plan = planner.plan(
            reminders: tasks.compactMap { $0.reminderSource() },
            bills: bills.map { $0.billSource() },
            now: now
        )

        center.removeAllPendingNotificationRequests()
        for notification in plan {
            do {
                try await center.add(Self.request(for: notification))
            } catch {
                logger.error("Couldn't schedule \(notification.identifier): \(error.localizedDescription)")
            }
        }
        logger.info("Scheduled \(plan.count) notifications")
    }

    /// The "Send test notification" button in Settings.
    func sendTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Notifications work"
        content.body = "This is how your reminders will arrive."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(identifier: "test", content: content, trigger: trigger))
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Asks iOS to wake the app in about 12 hours, for users who don't open it for days.
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func registerCategories() {
        let done = UNNotificationAction(identifier: NotificationAction.done.rawValue, title: "Done")
        let snooze = UNNotificationAction(identifier: NotificationAction.snoozeHour.rawValue, title: "Snooze 1 h")
        let paid = UNNotificationAction(identifier: NotificationAction.markPaid.rawValue, title: "Mark paid")
        let tomorrow = UNNotificationAction(identifier: NotificationAction.remindTomorrow.rawValue, title: "Remind me tomorrow")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: PlannedNotification.Category.task.rawValue, actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: PlannedNotification.Category.bill.rawValue, actions: [paid, tomorrow], intentIdentifiers: []),
        ])
    }

    private static func request(for notification: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = notification.category.rawValue
        if let itemID = notification.itemID {
            content.threadIdentifier = itemID.uuidString
            content.userInfo[NotificationPayload.itemIDKey] = itemID.uuidString
        }
        if let occurrence = notification.occurrence {
            content.userInfo[NotificationPayload.occurrenceKey] = occurrence.timeIntervalSince1970
        }

        var calendar = Calendar.current
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger)
    }
}

enum NotificationAction: String {
    case done = "DONE"
    case snoozeHour = "SNOOZE_1H"
    case markPaid = "MARK_PAID"
    case remindTomorrow = "REMIND_TOMORROW"
}

enum NotificationPayload {
    static let itemIDKey = "itemID"
    static let occurrenceKey = "occurrence"
}
