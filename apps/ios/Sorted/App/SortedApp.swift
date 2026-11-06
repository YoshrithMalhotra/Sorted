import SortedKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct SortedApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer
    private let scheduler: ReminderScheduler
    private let notificationHandler: NotificationActionHandler
    private let capture = AppConfig.makeCaptureService()

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        container = try! ModelContainer(
            for: TaskItem.self, Bill.self, ShoppingList.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
        scheduler = ReminderScheduler(container: container)
        notificationHandler = NotificationActionHandler(container: container, scheduler: scheduler)
        UNUserNotificationCenter.current().delegate = notificationHandler
        ReminderScheduler.registerCategories()
        DefaultData.insertIfNeeded(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.reminderScheduler, scheduler)
                .environment(\.captureService, capture)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await scheduler.reschedule() }
            case .background: ReminderScheduler.scheduleBackgroundRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(ReminderScheduler.refreshTaskID)) {
            await scheduler.reschedule()
            ReminderScheduler.scheduleBackgroundRefresh()
        }
    }
}

extension EnvironmentValues {
    @Entry var reminderScheduler: ReminderScheduler?
    @Entry var captureService = CaptureService(parser: nil)
}

/// The lists every new account starts with.
enum DefaultData {
    @MainActor
    static func insertIfNeeded(into context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<ShoppingList>())) == 0 else { return }
        for (index, name) in ShoppingList.defaultNames.enumerated() {
            context.insert(ShoppingList(name: name, sortOrder: index))
        }
        try? context.save()
    }
}
