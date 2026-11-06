import SortedKit
import SwiftData
import SwiftUI

/// Overdue, Today and Next 7 days, each sorted by priority and then time.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.reminderScheduler) private var scheduler
    @Query(filter: #Predicate<TaskItem> { $0.completedAt == nil }, sort: \TaskItem.createdAt)
    private var tasks: [TaskItem]

    @State private var editing: TaskItem?
    @State private var isAdding = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let agenda = Agenda(tasks: tasks, now: timeline.date)
            List {
                AgendaSection(title: "Overdue", entries: agenda.overdue, tint: .red, actions: actions)
                AgendaSection(title: "Today", entries: agenda.today, tint: nil, actions: actions)
                AgendaSection(title: "Next 7 days", entries: agenda.upcoming, tint: nil, actions: actions)
                if !agenda.someday.isEmpty {
                    AgendaSection(title: "No date", entries: agenda.someday, tint: nil, actions: actions)
                }
            }
            .overlay {
                if agenda.isEmpty {
                    ContentUnavailableView(
                        "Nothing due",
                        systemImage: "checkmark.circle",
                        description: Text("Tap Ask anything and say what's on your mind.")
                    )
                }
            }
        }
        .navigationTitle("Today")
        .toolbar {
            Button("Add task", systemImage: "plus") { isAdding = true }
        }
        .sheet(item: $editing) { task in
            TaskEditor(task: task)
        }
        .sheet(isPresented: $isAdding) {
            TaskEditor(task: nil)
        }
    }

    private var actions: AgendaActions {
        AgendaActions(
            complete: { entry in
                withAnimation { entry.task.complete(occurrence: entry.occurrence) }
                commit()
            },
            snooze: { entry, option in
                guard let date = option.wakeDate(now: .now, in: .current, defaultTime: AppSettings.defaultReminderTime) else { return }
                withAnimation { entry.task.snooze(until: date) }
                commit()
            },
            edit: { editing = $0.task }
        )
    }

    private func commit() {
        try? context.save()
        Task { await scheduler?.reschedule() }
    }
}

/// One row on Today: a task and the occurrence it's showing.
struct AgendaEntry: Identifiable {
    var task: TaskItem
    var occurrence: Date?
    /// When it's due, taking a snooze into account.
    var effectiveDate: Date?

    var id: PersistentIdentifier { task.persistentModelID }
}

struct Agenda {
    var overdue: [AgendaEntry] = []
    var today: [AgendaEntry] = []
    var upcoming: [AgendaEntry] = []
    var someday: [AgendaEntry] = []

    var isEmpty: Bool { overdue.isEmpty && today.isEmpty && upcoming.isEmpty && someday.isEmpty }

    init(tasks: [TaskItem], now: Date, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let weekEnd = calendar.date(byAdding: .day, value: 8, to: startOfToday)!

        for task in tasks {
            guard task.dueAt != nil else {
                someday.append(AgendaEntry(task: task))
                continue
            }
            guard let occurrence = task.currentOccurrence(now: now) else { continue }
            let snoozed = task.snoozedUntil.flatMap { $0 > now ? $0 : nil }
            let entry = AgendaEntry(task: task, occurrence: occurrence, effectiveDate: snoozed ?? occurrence)
            let date = entry.effectiveDate!
            // An all-day task is overdue only once its day has passed.
            let isOverdue = task.allDay && snoozed == nil ? date < startOfToday : date < now

            if isOverdue {
                overdue.append(entry)
            } else if date < startOfTomorrow {
                today.append(entry)
            } else if date < weekEnd {
                upcoming.append(entry)
            }
        }

        let order: (AgendaEntry, AgendaEntry) -> Bool = { lhs, rhs in
            if lhs.task.priority != rhs.task.priority { return lhs.task.priority < rhs.task.priority }
            return (lhs.effectiveDate ?? .distantFuture) < (rhs.effectiveDate ?? .distantFuture)
        }
        overdue.sort(by: order)
        today.sort(by: order)
        upcoming.sort(by: order)
        someday.sort(by: order)
    }
}

struct AgendaActions {
    var complete: (AgendaEntry) -> Void
    var snooze: (AgendaEntry, SnoozeOption) -> Void
    var edit: (AgendaEntry) -> Void
}

private struct AgendaSection: View {
    var title: String
    var entries: [AgendaEntry]
    var tint: Color?
    var actions: AgendaActions

    var body: some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    Button { actions.edit(entry) } label: {
                        TaskRow(entry: entry, isOverdue: tint != nil)
                    }
                    .buttonStyle(.plain)
                    // Swipe right to complete, swipe left to snooze.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Done", systemImage: "checkmark") { actions.complete(entry) }
                            .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        ForEach(availableSnoozes, id: \.self) { option in
                            Button(option.title) { actions.snooze(entry, option) }
                                .tint(option == .oneHour ? .orange : option == .tonight ? .indigo : .blue)
                        }
                    }
                }
            } header: {
                Text(title).foregroundStyle(tint ?? .secondary)
            }
        }
    }

    private var availableSnoozes: [SnoozeOption] {
        // Swipe actions are listed from the edge inward.
        SnoozeOption.allCases.reversed().filter {
            $0.wakeDate(now: .now, in: .current, defaultTime: AppSettings.defaultReminderTime) != nil
        }
    }
}

private struct TaskRow: View {
    var entry: AgendaEntry
    var isOverdue: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .foregroundStyle(entry.task.priority == .high ? .red : .secondary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.task.title)
                HStack(spacing: 4) {
                    if let date = entry.effectiveDate {
                        if entry.task.snoozedUntil == date {
                            Image(systemName: "moon.zzz")
                        }
                        Text(DueFormat.string(for: date, allDay: entry.task.allDay && entry.task.snoozedUntil != date))
                    }
                    if let rule = entry.task.recurrence {
                        Image(systemName: "repeat")
                        Text(rule.summary)
                    }
                }
                .font(.caption)
                .foregroundStyle(isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            Spacer()
            if entry.task.priority == .high {
                Image(systemName: "exclamationmark")
                    .foregroundStyle(.red)
                    .accessibilityLabel("High priority")
            }
        }
        .contentShape(.rect)
    }
}

#Preview {
    NavigationStack { TodayView() }
        .modelContainer(PreviewData.container)
}
