import SortedKit
import SwiftData
import SwiftUI

/// Say it once: a sentence in, confirmation cards out. Nothing saves until Save.
struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.captureService) private var captureService
    @Environment(\.reminderScheduler) private var scheduler
    @Query(sort: \ShoppingList.sortOrder) private var lists: [ShoppingList]

    @State private var text = ""
    @State private var isParsing = false
    @State private var drafts: [CaptureDraft] = []
    @State private var outcome: CaptureService.Outcome?
    @State private var reply = ""
    @FocusState private var isTextFocused: Bool

    private static let example = "Remind me to drink water every 2 hours from 9 to 6"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pay rent on the 1st every month, 25,000", text: $text, axis: .vertical)
                        .focused($isTextFocused)
                        .submitLabel(.go)
                        .onSubmit { Task { await parse() } }
                        .disabled(isParsing)
                } footer: {
                    if drafts.isEmpty, !isParsing {
                        Button("Try \u{201C}\(Self.example)\u{201D}") {
                            text = Self.example
                            Task { await parse() }
                        }
                        .font(.footnote)
                    }
                }

                if isParsing {
                    Section { LoadingCard() }
                }

                if let note = outcome?.note {
                    Section { Label(note, systemImage: "info.circle").foregroundStyle(.secondary) }
                }

                if let question = drafts.compactMap(\.question).first {
                    Section("One question") {
                        Text(question)
                        TextField("Your answer", text: $reply)
                            .onSubmit { Task { await answer() } }
                    }
                }

                ForEach($drafts) { $draft in
                    ConfirmationCard(draft: $draft, listNames: lists.map(\.name)) {
                        drafts.removeAll { $0.id == draft.id }
                    }
                }
            }
            .navigationTitle("Say it once")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if drafts.isEmpty {
                        Button("Go") { Task { await parse() } }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
                    } else {
                        Button(drafts.count > 1 ? "Save all" : "Save", action: save)
                    }
                }
            }
            .onAppear { isTextFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func parse(_ input: String? = nil) async {
        let sentence = (input ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        isParsing = true
        isTextFocused = false
        let listNames = lists.map(\.name)
        let request = ParseRequest(text: sentence, timeZone: .current, locale: .current, now: .now, listNames: listNames)
        let result = await captureService.capture(request)
        withAnimation {
            drafts = result.items.map { CaptureDraft($0, listNames: listNames) }
            outcome = result.outcome
            isParsing = false
        }
    }

    /// Sends the sentence again with the answer to the clarifying question.
    private func answer() async {
        let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        reply = ""
        await parse("\(text.trimmingCharacters(in: .whitespacesAndNewlines)). \(answer)")
    }

    private func save() {
        var needsNotifications = false
        for draft in drafts {
            needsNotifications = draft.save(in: context, lists: lists) || needsNotifications
        }
        try? context.save()
        dismiss()
        guard needsNotifications, let scheduler else { return }
        Task {
            // The first dated item is the moment the permission prompt makes sense.
            _ = await scheduler.requestAuthorization()
            await scheduler.reschedule()
        }
    }
}

private extension CaptureService.Outcome {
    var note: String? {
        switch self {
        case .parsed: nil
        case .noItems: "That didn't read as a reminder, so here it is as a task. Edit it before saving."
        case .failed: "Couldn't reach Sorted's AI, so here it is as a plain task. Nothing you typed is lost."
        }
    }
}

/// The shimmer shown while the parse call runs (about 1–2 seconds).
private struct LoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pay electricity bill").font(.headline)
            Text("Bill · Monthly on the 5th · Reminder 3 days before").font(.subheadline)
        }
        .redacted(reason: .placeholder)
        .phaseAnimator([0.4, 1]) { view, opacity in
            view.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 0.8) }
        .accessibilityLabel("Reading your sentence")
    }
}

#Preview {
    CaptureSheet()
        .modelContainer(PreviewData.container)
}
