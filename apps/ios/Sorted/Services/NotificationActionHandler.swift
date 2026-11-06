import Foundation
import SortedKit
import SwiftData
import UserNotifications

/// Runs notification actions (Done, Snooze 1 h, Mark paid, Remind me tomorrow)
/// without opening the app, then reschedules.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let container: ModelContainer
    private let scheduler: ReminderScheduler

    init(container: ModelContainer, scheduler: ReminderScheduler) {
        self.container = container
        self.scheduler = scheduler
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard let action = NotificationAction(rawValue: response.actionIdentifier),
              let idString = content.userInfo[NotificationPayload.itemIDKey] as? String,
              let id = UUID(uuidString: idString) else { return }
        let occurrence = (content.userInfo[NotificationPayload.occurrenceKey] as? TimeInterval)
            .map(Date.init(timeIntervalSince1970:))

        await perform(action, itemID: id, occurrence: occurrence)
    }

    @MainActor
    private func perform(_ action: NotificationAction, itemID: UUID, occurrence: Date?) async {
        let context = container.mainContext
        switch action {
        case .done:
            let task = try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == itemID })).first
            task?.complete(occurrence: occurrence)
        case .snoozeHour:
            let task = try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == itemID })).first
            task?.snooze(until: .now.addingTimeInterval(3600))
        case .markPaid:
            let bill = try? context.fetch(FetchDescriptor<Bill>(predicate: #Predicate { $0.id == itemID })).first
            if let bill { bill.markPaid(dueOn: occurrence ?? bill.nextDueOn) }
        case .remindTomorrow:
            let bill = try? context.fetch(FetchDescriptor<Bill>(predicate: #Predicate { $0.id == itemID })).first
            bill?.snoozedUntil = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        }
        try? context.save()
        await scheduler.reschedule()
    }
}
