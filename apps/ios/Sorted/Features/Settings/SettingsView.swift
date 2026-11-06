import SortedKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.reminderScheduler) private var scheduler
    @AppStorage(AppSettings.defaultReminderMinutesKey) private var defaultReminderMinutes = TimeOfDay.defaultReminder.minutesSinceMidnight

    @State private var authorization = UNAuthorizationStatus.notDetermined
    @State private var testMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Account", value: "Not signed in")
                LabeledContent("Plan", value: "Free")
            } header: {
                Text("Account")
            } footer: {
                Text("Sign in with Apple and sync arrive with the Supabase backend. Until then everything stays on this iPhone.")
            }

            Section {
                DatePicker("Default reminder time", selection: defaultTime, displayedComponents: .hourAndMinute)
                switch authorization {
                case .notDetermined:
                    Button("Turn on notifications") { Task { await requestNotifications() } }
                case .denied:
                    Button("Notifications are off. Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                default:
                    Button("Send test notification") { Task { await sendTest() } }
                }
            } header: {
                Text("Reminders")
            } footer: {
                if let testMessage {
                    Text(testMessage)
                } else {
                    Text("Items without a time remind you at this time.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.versionString)
            }
        }
        .navigationTitle("Settings")
        .task { await refreshAuthorization() }
        .onChange(of: defaultReminderMinutes) {
            Task { await scheduler?.reschedule() }
        }
    }

    private var defaultTime: Binding<Date> {
        Binding(
            get: { TimeOfDay(minutesSinceMidnight: defaultReminderMinutes).on(.now, in: .current) },
            set: {
                let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
                defaultReminderMinutes = TimeOfDay(hour: components.hour ?? 9, minute: components.minute ?? 0).minutesSinceMidnight
            }
        )
    }

    private func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotifications() async {
        _ = await scheduler?.requestAuthorization()
        await refreshAuthorization()
        await scheduler?.reschedule()
    }

    private func sendTest() async {
        do {
            try await scheduler?.sendTestNotification()
            testMessage = "A test notification arrives in 5 seconds. Lock your iPhone to see it."
        } catch {
            testMessage = "Couldn't schedule the test: \(error.localizedDescription)"
        }
    }
}

private extension Bundle {
    var versionString: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
