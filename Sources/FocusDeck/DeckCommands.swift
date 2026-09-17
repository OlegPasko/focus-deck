import SwiftUI
import FocusDeckKit

/// Menu bar commands and keyboard shortcuts.
struct DeckCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore

    init(model: AppModel) {
        self.model = model
        self._settings = ObservedObject(wrappedValue: model.settings)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Set Focus Text…") {
                guard !model.isCreatingTask else { return }
                model.draftError = nil
                model.draftTitle = model.store.state.current?.title ?? ""
                model.isEditingFocus = true
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Pick Task from Todoist…") {
                model.showsPicker = true
            }
            .keyboardShortcut("k", modifiers: [.command])
        }

        CommandMenu("Focus") {
            Button("Done, Next Task") { model.completeCurrent() }
                .keyboardShortcut("d", modifiers: [.command])
            Button("Refresh Todoist") { Task { await model.refreshTodoist() } }
                .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Bigger Text") { adjustScale(by: 0.1) }
                .keyboardShortcut("+", modifiers: [.command])
            Button("Smaller Text") { adjustScale(by: -0.1) }
                .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button("Move to Next Display") { DeckWindow.shared.moveToNextDisplay() }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option])
            Button("Fill This Display") { DeckWindow.shared.fillCurrentDisplay() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Center on This Display") { DeckWindow.shared.center() }
            Button("Toggle Full Screen") { DeckWindow.shared.toggleFullScreen() }
                .keyboardShortcut("f", modifiers: [.control, .command])
            Toggle("Foreground of all windows", isOn: Binding(
                get: { settings.settings.alwaysOnTop },
                set: { settings.settings.alwaysOnTop = $0; DeckWindow.shared.applyAlwaysOnTop($0) }))
        }

        CommandGroup(replacing: .appSettings) {
            Button("Focus Deck Settings…") { model.showsSettings = true }
                .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private func adjustScale(by delta: Double) {
        let next = min(2.5, max(0.4, model.settings.settings.textScale + delta))
        model.settings.settings.textScale = next
        model.flash(String(format: "Text scale %.0f%%", next * 100), kind: "info")
    }
}
