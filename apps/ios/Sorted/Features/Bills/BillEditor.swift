import SortedKit
import SwiftData
import SwiftUI

/// Adds a bill by hand, or edits one: amount, schedule, autopay and alerts.
struct BillEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.reminderScheduler) private var scheduler

    let bill: Bill?

    @State private var name = ""
    @State private var amount: Decimal?
    @State private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var nextDueOn = Date.now
    @State private var rrule: String? = "FREQ=MONTHLY"
    @State private var category = ""
    @State private var autopay = false
    @State private var remindDaysBefore = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Amount") {
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Currency", text: $currency)
                        .textInputAutocapitalization(.characters)
                    TextField("Category", text: $category)
                }
                Section {
                    DatePicker("Next due", selection: $nextDueOn, displayedComponents: .date)
                    RepeatPicker(rrule: $rrule)
                    Toggle("Autopay", isOn: $autopay)
                    Stepper(value: $remindDaysBefore, in: 0...14) {
                        LabeledContent("Remind me", value: remindDaysBefore == 0 ? "On the day" : "\(remindDaysBefore) days before")
                    }
                } footer: {
                    Text("Sorted never stores card or account numbers, only the name, amount and schedule.")
                }
                if let bill {
                    Section {
                        Button("Delete Bill", role: .destructive) {
                            context.delete(bill)
                            commit()
                        }
                    }
                }
            }
            .navigationTitle(bill == nil ? "New Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let bill else { return }
        name = bill.name
        amount = bill.amount
        currency = bill.currency
        nextDueOn = bill.nextDueOn
        rrule = bill.rrule
        category = bill.category ?? ""
        autopay = bill.autopay
        remindDaysBefore = bill.remindDaysBefore
    }

    private func save() {
        let target = bill ?? {
            let new = Bill(name: name, nextDueOn: nextDueOn)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.amount = amount
        target.currency = currency.uppercased()
        target.nextDueOn = Calendar.current.startOfDay(for: nextDueOn)
        target.rrule = rrule
        target.category = category.isEmpty ? nil : category
        target.autopay = autopay
        target.remindDaysBefore = remindDaysBefore
        target.updatedAt = .now
        commit()
    }

    private func commit() {
        try? context.save()
        dismiss()
        Task { await scheduler?.reschedule() }
    }
}
