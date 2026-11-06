import Foundation

/// Finds the occurrence of a task the user should act on now.
public enum Occurrences {
    /// The latest missed occurrence if there is one, otherwise the next one.
    ///
    /// Missed occurrences collapse into one: a daily task skipped for three
    /// days shows once as overdue, not three times. Completing it moves the
    /// task on to its next future occurrence.
    ///
    /// - Parameters:
    ///   - rule: The task's rule, or nil for a one-off task.
    ///   - start: The first occurrence (`due_at`).
    ///   - completed: The `occurrence_at` of every row in `task_completions`.
    /// - Returns: nil when there is nothing left to do.
    public static func current(
        rule: RecurrenceRule?,
        start: Date,
        in timeZone: TimeZone,
        completed: Set<Date>,
        now: Date
    ) -> Date? {
        guard let rule else { return completed.isEmpty ? start : nil }

        let lastDone = completed.max()
        let lower = max(start, lastDone.map { $0.addingTimeInterval(1) } ?? start)
        if lower <= now {
            let missed = rule.occurrences(startingAt: start, in: timeZone, from: lower, to: now.addingTimeInterval(1))
            if let latest = missed.last(where: { !completed.contains($0) }) { return latest }
        }
        let after = max(now, lastDone ?? now)
        return rule.nextOccurrence(after: after, startingAt: start, in: timeZone)
    }
}
