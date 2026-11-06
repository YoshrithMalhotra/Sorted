import Foundation
import SortedKit
import SwiftData

/// A row of `tasks`. A reminder is a task with `remind == true`.
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    /// Set once the account syncs to Supabase.
    var householdID: UUID?
    var title: String
    var notes: String?
    /// The first occurrence. For an all-day task, the start of that local day.
    var dueAt: Date?
    var allDay: Bool
    var rrule: String?
    var priorityRaw: String
    var remind: Bool
    /// Only for one-off tasks. A recurring task records each occurrence in `completions`.
    var completedAt: Date?
    var snoozedUntil: Date?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TaskCompletion.task)
    var completions: [TaskCompletion] = []

    init(
        title: String, notes: String? = nil, dueAt: Date? = nil, allDay: Bool = false,
        rrule: String? = nil, priority: Priority = .normal, remind: Bool = false
    ) {
        id = UUID()
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.allDay = allDay
        self.rrule = rrule
        priorityRaw = priority.rawValue
        self.remind = remind
        createdAt = .now
        updatedAt = .now
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var recurrence: RecurrenceRule? {
        rrule.flatMap { try? RecurrenceRule($0) }
    }

    var completedOccurrences: Set<Date> {
        Set(completions.map(\.occurrenceAt))
    }

    /// The occurrence Today shows: the latest missed one, or the next one.
    func currentOccurrence(now: Date = .now, in timeZone: TimeZone = .current) -> Date? {
        guard completedAt == nil, let dueAt else { return nil }
        return Occurrences.current(
            rule: recurrence, start: dueAt, in: timeZone, completed: completedOccurrences, now: now
        )
    }

    /// Completes one occurrence: the current one unless another is named.
    func complete(occurrence: Date? = nil, now: Date = .now, in timeZone: TimeZone = .current) {
        if recurrence != nil, let occurrence = occurrence ?? currentOccurrence(now: now, in: timeZone) {
            completions.append(TaskCompletion(occurrenceAt: occurrence, completedAt: now))
        } else {
            completedAt = now
        }
        snoozedUntil = nil
        updatedAt = now
    }

    func snooze(until date: Date) {
        snoozedUntil = date
        updatedAt = .now
    }

    func reminderSource() -> ReminderSource? {
        guard remind, completedAt == nil, let dueAt else { return nil }
        return ReminderSource(
            id: id, title: title, notes: notes, start: dueAt, allDay: allDay, rule: recurrence,
            completedOccurrences: completedOccurrences, snoozedUntil: snoozedUntil
        )
    }
}

/// A row of `task_completions`: one finished occurrence of a recurring task.
@Model
final class TaskCompletion {
    var occurrenceAt: Date
    var completedAt: Date
    var task: TaskItem?

    init(occurrenceAt: Date, completedAt: Date) {
        self.occurrenceAt = occurrenceAt
        self.completedAt = completedAt
    }
}
