import SortedKit
import SwiftUI

/// Picks a repeat: never, the common presets, or the custom rule already set.
struct RepeatPicker: View {
    @Binding var rrule: String?

    private static let presets: [(String, String)] = [
        ("Daily", "FREQ=DAILY"),
        ("Weekdays", "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"),
        ("Weekly", "FREQ=WEEKLY"),
        ("Every 2 weeks", "FREQ=WEEKLY;INTERVAL=2"),
        ("Monthly", "FREQ=MONTHLY"),
        ("Yearly", "FREQ=YEARLY"),
    ]

    var body: some View {
        Picker("Repeat", selection: $rrule) {
            Text("Never").tag(String?.none)
            ForEach(Self.presets, id: \.1) { title, rule in
                Text(title).tag(Optional(rule))
            }
            // A rule from the parser, such as "the last Friday", stays selectable.
            if let rrule, !Self.presets.contains(where: { $0.1 == rrule }) {
                Text((try? RecurrenceRule(rrule))?.summary ?? rrule).tag(Optional(rrule))
            }
        }
    }
}
