import SortedKit
import SwiftData
import SwiftUI

/// What's due in the next 30 days, upcoming bills by date, and what's paid this month.
struct BillsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.reminderScheduler) private var scheduler
    @Query(sort: \Bill.nextDueOn) private var bills: [Bill]
    @Query(sort: \BillPayment.paidOn, order: .reverse) private var payments: [BillPayment]

    @State private var editing: Bill?
    @State private var isAdding = false

    var body: some View {
        let now = Date.now
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: now))!
        let upcoming = bills
            .flatMap { bill in bill.unpaidDueDates(before: horizon, now: now).map { DueBill(bill: bill, dueOn: $0) } }
            .sorted { $0.dueOn < $1.dueOn }
        let paidThisMonth = payments.filter { calendar.isDate($0.paidOn, equalTo: now, toGranularity: .month) }

        List {
            Section {
                OutgoingTotal(upcoming: upcoming)
            }

            Section("Upcoming") {
                if upcoming.isEmpty {
                    Text("No bills due in the next 30 days").foregroundStyle(.secondary)
                }
                ForEach(upcoming) { due in
                    BillRow(due: due, now: now)
                        .contentShape(.rect)
                        .onTapGesture { editing = due.bill }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Mark paid", systemImage: "checkmark") {
                                withAnimation { due.bill.markPaid(dueOn: due.dueOn) }
                                commit()
                            }
                            .tint(.green)
                        }
                        .contextMenu {
                            Button("Mark paid", systemImage: "checkmark") {
                                due.bill.markPaid(dueOn: due.dueOn)
                                commit()
                            }
                            Toggle("Autopay", systemImage: "arrow.triangle.2.circlepath", isOn: Binding(
                                get: { due.bill.autopay },
                                set: { due.bill.autopay = $0; due.bill.updatedAt = .now; commit() }
                            ))
                            Button("Edit", systemImage: "pencil") { editing = due.bill }
                        }
                }
            }

            if !paidThisMonth.isEmpty {
                Section("Paid this month") {
                    ForEach(paidThisMonth) { payment in
                        LabeledContent {
                            if let amount = payment.amountPaid, let bill = payment.bill {
                                Text(amount, format: .currency(code: bill.currency))
                            }
                        } label: {
                            Text(payment.bill?.name ?? "Bill")
                            Text("Paid \(payment.paidOn.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                }
            }
        }
        .navigationTitle("Bills")
        .toolbar {
            Button("Add bill", systemImage: "plus") { isAdding = true }
        }
        .sheet(item: $editing) { BillEditor(bill: $0) }
        .sheet(isPresented: $isAdding) { BillEditor(bill: nil) }
    }

    private func commit() {
        try? context.save()
        Task { await scheduler?.reschedule() }
    }
}

struct DueBill: Identifiable {
    var bill: Bill
    var dueOn: Date
    var id: String { "\(bill.id)-\(dueOn.timeIntervalSince1970)" }
}

/// The 30-day outgoing total, one line per currency.
private struct OutgoingTotal: View {
    var upcoming: [DueBill]

    var body: some View {
        let totals = Dictionary(grouping: upcoming, by: \.bill.currency)
            .mapValues { $0.reduce(Decimal.zero) { $0 + ($1.bill.amount ?? 0) } }
            .sorted { $0.key < $1.key }

        VStack(alignment: .leading, spacing: 4) {
            Text("Due in the next 30 days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if totals.isEmpty {
                Text(Decimal.zero, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.largeTitle.bold())
            }
            ForEach(totals, id: \.key) { currency, total in
                Text(total, format: .currency(code: currency))
                    .font(.largeTitle.bold())
                    .contentTransition(.numericText())
            }
            Text("\(upcoming.count) \(upcoming.count == 1 ? "payment" : "payments")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct BillRow: View {
    var due: DueBill
    var now: Date

    var body: some View {
        let isOverdue = due.dueOn < Calendar.current.startOfDay(for: now)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(due.bill.name)
                HStack(spacing: 4) {
                    Text(DueFormat.string(for: due.dueOn, allDay: true, now: now))
                    if due.bill.autopay {
                        Label("Autopay", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .font(.caption)
                .foregroundStyle(isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            Spacer()
            if let amount = due.bill.amount {
                Text(amount, format: .currency(code: due.bill.currency))
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    NavigationStack { BillsView() }
        .modelContainer(PreviewData.container)
}
