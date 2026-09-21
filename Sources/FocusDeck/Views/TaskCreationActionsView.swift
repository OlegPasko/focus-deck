import SwiftUI

struct TaskCreationActionsView: View {
    let isCreating: Bool
    let isDisabled: Bool
    let submit: (TaskCreationAction) -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Cancel", action: cancel)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(isCreating)
            Spacer(minLength: 0)
            Button("Add to Today") { submit(.next) }
                .help("Make this your next task in Focus Deck without changing your current focus.")
                .disabled(isDisabled)
            Button(isCreating ? "Adding to Today…" : "Add to Today & focus") { submit(.focus) }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.52, green: 0.40, blue: 0.69))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(isDisabled)
        }
        .controlSize(.small)
        .font(.system(size: 12))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
}
