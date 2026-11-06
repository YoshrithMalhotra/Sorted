import SortedKit
import SwiftData
import SwiftUI

/// Adds a task by hand, or edits every field of an existing one.
struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.reminderScheduler) private var scheduler

    let task: TaskItem?

    @State private var title = ""
    @State private var notes = ""
    @State private var dueAt: Date?
    @State private var allDay = false
    @State private var rrule: String?
    @State private var priority = Priority.normal
    @State private var remind = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section {
                    Toggle("Date", isOn: Binding(
                        get: { dueAt != nil },
                        set: { dueAt = $0 ? (dueAt ?? DueFields.nextRoundHour()) : nil }
                    ))
                    if let date = dueAt {
                        Toggle("All day", isOn: $allDay)
                        DatePicker(
                            "When",
                            selection: Binding(get: { date }, set: { dueAt = $0 }),
                            displayedComponents: allDay ? .date : [.date, .hourAndMinute]
                        )
                        RepeatPicker(rrule: $rrule)
                        Toggle("Notify me", isOn: $remind)
                    }
                }
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                if let task {
                    Section {
                        Button("Delete Task", role: .destructive) {
                            context.delete(task)
                            commit()
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let task else { return }
        title = task.title
        notes = task.notes ?? ""
        dueAt = task.dueAt
        allDay = task.allDay
        rrule = task.rrule
        priority = task.priority
        remind = task.remind
    }

    private func save() {
        let target = task ?? {
            let new = TaskItem(title: title)
            context.insert(new)
            return new
        }()
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.notes = notes.isEmpty ? nil : notes
        target.dueAt = allDay ? dueAt.map(Calendar.current.startOfDay(for:)) : dueAt
        target.allDay = allDay
        target.rrule = dueAt == nil ? nil : rrule
        target.priority = priority
        target.remind = dueAt != nil && remind
        target.updatedAt = .now
        commit()
    }

    private func commit() {
        try? context.save()
        dismiss()
        Task { await scheduler?.reschedule() }
    }
}
