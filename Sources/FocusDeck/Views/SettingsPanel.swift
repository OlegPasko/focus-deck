import SwiftUI
import FocusDeckKit

struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var tokenDraft = ""
    @State private var filterDraft = ""

    init(model: AppModel) {
        self.model = model
        self._settings = ObservedObject(wrappedValue: model.settings)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { model.showsSettings = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    group("Text") {
                        slider("Text scale", value: $settings.settings.textScale, range: 0.4...2.5)
                        toggle("CAPITAL LETTERS", isOn: $settings.settings.uppercase)
                        toggle("Show task detail line", isOn: $settings.settings.showCoverTitle)
                        toggle("Show clock", isOn: $settings.settings.showClock)
                        toggle("Show time on task", isOn: $settings.settings.showElapsed)
                        toggle("Show next task on hover", isOn: $settings.settings.showQueue)
                    }
                    group("Cover and animation") {
                        Picker("Wallpaper", selection: $settings.settings.coverStyle) {
                            Text("Gallery · one image per task").tag("gallery")
                            ForEach(ArtworkCatalog.wallpapers) { wallpaper in
                                Text(wallpaper.title).tag(wallpaper.id)
                            }
                            Text("Plain midnight").tag("plain")
                            Text("Classic animated synthwave").tag("classic")
                        }
                        Text("Gallery keeps one image per task and changes only with the task. Choose a wallpaper to keep one static image. No timed rotation.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        toggle("Animate task transitions", isOn: $settings.settings.animationEnabled)
                        if settings.settings.coverStyle == "classic" {
                            slider("Ambient motion", value: $settings.settings.animationIntensity, range: 0...1)
                            palettePicker
                        }
                        slider("Slide duration", value: $settings.settings.slideDuration, range: 0.2...2.0)
                        slider("Darken cover", value: $settings.settings.backdropDarkness, range: 0...0.8)
                        slider("Darken behind the title", value: $settings.settings.titleScrimStrength, range: 0...0.7)
                    }
                    group("Window") {
                        toggle("Foreground of all windows", isOn: $settings.settings.alwaysOnTop)
                            .onChange(of: settings.settings.alwaysOnTop) { value in
                                DeckWindow.shared.applyAlwaysOnTop(value)
                            }
                        toggle("Start Focus Deck at login", isOn: $settings.settings.startAtLogin)
                            .onChange(of: settings.settings.startAtLogin) { value in
                                model.applyStartAtLogin(value)
                            }
                        Text("The window remembers its position, so it can stay on your second display.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        HStack {
                            Button("Move to next display") { DeckWindow.shared.moveToNextDisplay() }
                            Button("Fill this display") { DeckWindow.shared.fillCurrentDisplay() }
                            Button("Center") { DeckWindow.shared.center() }
                        }
                        .buttonStyle(.bordered)
                    }
                    group("Calendar") {
                        CalendarSettingsView(calendar: model.calendar, settings: settings)
                    }
                    group("Todoist") {
                        Text("Paste your Todoist API token (Todoist → Settings → Integrations → Developer). It is stored in the macOS keychain.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                        HStack {
                            SecureField(settings.settings.todoistTokenPresent ? "token saved" : "API token",
                                        text: $tokenDraft)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") { model.saveTodoistToken(tokenDraft); tokenDraft = "" }
                                .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if settings.settings.todoistTokenPresent {
                                Button("Disconnect") { model.saveTodoistToken("") }
                            }
                        }
                        HStack {
                            Text("Filter")
                            TextField("today, ##Work, @errand …", text: $filterDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { model.setTodoistFilter(filterDraft) }
                            Button("Apply") { model.setTodoistFilter(filterDraft) }
                        }
                        toggle("Sync from Todoist", isOn: $settings.settings.todoistEnabled)
                            .onChange(of: settings.settings.todoistEnabled) { _ in
                                model.scheduleTodoistRefresh()
                            }
                        slider("Refresh every N minutes", value: $settings.settings.todoistRefreshMinutes, range: 1...60)
                            .onChange(of: settings.settings.todoistRefreshMinutes) { _ in
                                model.scheduleTodoistRefresh()
                            }
                        if let message = model.todoistMessage {
                            Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        }
                        HStack {
                            Button("Test connection") {
                                Task {
                                    guard let token = KeychainStore.todoistToken else {
                                        model.todoistMessage = "No token saved."
                                        return
                                    }
                                    do {
                                        _ = try await TodoistClient(token: token).projects(limit: 1, maxPages: 1)
                                        model.todoistMessage = "Todoist connection OK."
                                    } catch {
                                        model.todoistMessage = error.localizedDescription
                                    }
                                }
                            }
                            Button("Sync now") { Task { await model.refreshTodoist() } }
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack {
                        Button("Close") { model.showsSettings = false }
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                }
                .padding(26)
            }
            .frame(maxWidth: 700, maxHeight: 620)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(36)
        }
        .onAppear { filterDraft = settings.settings.todoistFilter }
    }

    private var header: some View {
        HStack {
            Text("FOCUS DECK SETTINGS")
                .font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(3)
            Spacer()
        }
        .foregroundStyle(.white)
    }

    private var palettePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Palette").font(.system(size: 13, weight: .semibold))
            Picker("", selection: Binding(
                get: { settings.settings.paletteOverride ?? -1 },
                set: { settings.settings.paletteOverride = $0 < 0 ? nil : $0 })) {
                Text("From task").tag(-1)
                ForEach(Array(SynthPalette.catalog.enumerated()), id: \.offset) { index, palette in
                    Text(palette.name).tag(index)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.55))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
    }

    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(label).font(.system(size: 13)) }
            .toggleStyle(.switch)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13))
            Slider(value: value, in: range)
        }
    }
}
