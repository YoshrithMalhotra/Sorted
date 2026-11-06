import SortedKit
import SwiftUI

/// One parsed item, with every field editable before it saves.
struct ConfirmationCard: View {
    @Binding var draft: CaptureDraft
    var listNames: [String]
    var onRemove: () -> Void

    var body: some View {
        Section {
            TextField("Title", text: $draft.title)
                .font(.headline)

            Picker("Type", selection: $draft.kind) {
                ForEach(CaptureKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            switch draft.kind {
            case .reminder, .task:
                DueFields(draft: $draft)
                Picker("Priority", selection: $draft.priority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.rawValue.capitalized).tag(priority)
                    }
                }
            case .bill:
                LabeledContent("Amount") {
                    TextField("Amount", value: $draft.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Currency", text: $draft.currency)
                    .textInputAutocapitalization(.characters)
                DatePicker("Due", selection: dueDateBinding, displayedComponents: .date)
                RepeatPicker(rrule: $draft.rrule)
            case .shoppingItem:
                Picker("List", selection: $draft.listName) {
                    ForEach(Array(Set(listNames + [draft.listName])).sorted(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                TextField("Aisle", text: Binding(
                    get: { draft.category ?? "" },
                    set: { draft.category = $0.isEmpty ? nil : $0 }
                ))
            }
        } header: {
            HStack {
                Text(draft.summary)
                    .textCase(nil)
                    .lineLimit(2)
                Spacer()
                Button("Remove", systemImage: "xmark.circle.fill", action: onRemove)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dueDateBinding: Binding<Date> {
        Binding(get: { draft.dueDate ?? .now }, set: { draft.dueDate = $0 })
    }
}

/// Date, time and repeat for a task or reminder.
struct DueFields: View {
    @Binding var draft: CaptureDraft

    var body: some View {
        Toggle("Date", isOn: Binding(
            get: { draft.dueDate != nil },
            set: { draft.dueDate = $0 ? (draft.dueDate ?? Self.nextRoundHour()) : nil }
        ))
        if let dueDate = draft.dueDate {
            Toggle("All day", isOn: $draft.allDay)
            DatePicker(
                "When",
                selection: Binding(get: { dueDate }, set: { draft.dueDate = $0 }),
                displayedComponents: draft.allDay ? .date : [.date, .hourAndMinute]
            )
            RepeatPicker(rrule: $draft.rrule)
        }
    }

    static func nextRoundHour(after date: Date = .now) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? date
    }
}
