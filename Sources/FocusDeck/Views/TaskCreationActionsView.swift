import SwiftUI

struct TaskCreationActionsView: View {
    let isCreating: Bool
    let isDisabled: Bool
    let submit: (TaskCreationAction) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { captureButtons }
                VStack(alignment: .leading, spacing: 10) { captureButtons }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(isDisabled)
            HStack {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(isCreating)
                Spacer()
                Button(isCreating ? "Adding to Today…" : "Add to Today & focus") { submit(.focus) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.52, green: 0.40, blue: 0.69))
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isDisabled)
            }
        }
    }

    @ViewBuilder
    private var captureButtons: some View {
        Button("Just add to Today") { submit(.today) }
            .help("Save to Todoist Today and keep your current focus.")
        Button("Add to Today & make next") { submit(.next) }
            .help("Keep your current focus. Choose this task next when you finish it in Focus Deck.")
    }
}
