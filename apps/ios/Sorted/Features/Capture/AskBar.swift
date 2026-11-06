import SwiftUI

/// The pinned "Ask anything" bar. One tap opens capture with the keyboard up.
struct AskBar: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Ask anything")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .modifier(AskBarBackground())
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask anything")
        .accessibilityHint("Type or dictate a reminder, bill or shopping item")
    }
}

/// On iOS 26 the tab view's accessory draws the glass, so the bar adds none.
private struct AskBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.background(.regularMaterial, in: .capsule)
        }
    }
}

#Preview {
    AskBar {}
        .padding()
}
