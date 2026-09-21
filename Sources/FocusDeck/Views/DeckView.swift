import SwiftUI
import FocusDeckKit

struct DeckView: View {
    @ObservedObject var model: AppModel
    var startsModel: Bool = true
    @ObservedObject private var store: FocusStore
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var calendar: CalendarController
    @ObservedObject private var deckWindow = DeckWindow.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showChrome = true
    @State private var controlsHovered = false
    @State private var chromeTask: Task<Void, Never>?
    @SwiftUI.FocusState private var editorFocused: Bool

    init(model: AppModel, startsModel: Bool = true) {
        self.startsModel = startsModel
        self.model = model
        self._store = ObservedObject(wrappedValue: model.store)
        self._settings = ObservedObject(wrappedValue: model.settings)
        self._calendar = ObservedObject(wrappedValue: model.calendar)
    }

    private var current: FocusItem? { store.state.current }
    private var chromeVisible: Bool { showChrome || controlsHovered || current == nil }

    var body: some View {
        GeometryReader { geometry in
            let margin = max(24, min(100, geometry.size.width * 0.085))
            ZStack {
                CoverStageView(item: current, settings: settings.settings,
                    isWindowVisible: deckWindow.isVisible,
                    ambientFrameRate: deckWindow.isKey ? 24 : 12)
                    .ignoresSafeArea()
                Color.black.opacity(settings.settings.backdropDarkness).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.12), .clear, .black.opacity(0.25)],
                    startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)

                FocusTitleView(item: current, settings: settings.settings, emptyText: model.emptyFocusText,
                               meeting: calendar.reminder(at: model.now), now: model.now)
                    .frame(width: max(1, geometry.size.width - margin * 2),
                           height: max(80, geometry.size.height * 0.50))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.44)
                    .onTapGesture(count: 2) { editFocus() }

                VStack {
                    header
                    Spacer(minLength: 0)
                    footer(compact: geometry.size.width < 600)
                }
                .padding(.horizontal, max(20, margin * 0.55))
                .padding(.top, 26)
                .padding(.bottom, 22)
                .overlay(alignment: .bottomLeading) {
                    EverlabsLinkView(visible: chromeVisible)
                        .padding(.leading, max(20, margin * 0.55))
                        .padding(.bottom, 22)
                }
                .overlay(alignment: .bottomTrailing) {
                    SpotifyControlView(player: model.spotify, isWindowVisible: deckWindow.isVisible)
                        .padding(.trailing, max(20, margin * 0.55))
                        .padding(.bottom, 22)
                }

                if let overlay = store.activeOverlay(at: model.now) {
                    VStack {
                        OverlayBannerView(message: overlay).padding(.top, 68)
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
                if model.isEditingFocus { editSheet }
                if model.showsSettings { SettingsPanel(model: model) }
                if model.showsPicker { PickerPanel(model: model) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .onAppear { if startsModel { model.start() }; revealChrome() }
        .background(PointerHoverRegion { inside in
            if inside { revealChrome() } else { showChrome = false }
        })
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: chromeVisible)
        .onDisappear { chromeTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 15))
            Text("FOCUS DECK").font(.system(size: 10, weight: .semibold)).tracking(3)
            Spacer(minLength: 12)
            if settings.settings.showElapsed, let elapsed = current?.elapsed(now: model.now) {
                Text(Self.durationLabel(elapsed) + " focused")
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            if settings.settings.showClock {
                Text(model.now, style: .time).font(.system(size: 11)).monospacedDigit()
            }
            Button { model.showsSettings = true } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.white.opacity(chromeVisible ? 0.65 : 0.38))
        .onHover { controlsHovered = $0 }
    }

    private func footer(compact: Bool) -> some View {
        VStack(spacing: 16) {
            if settings.settings.showQueue, settings.settings.todoistTokenPresent {
                HStack(spacing: 10) {
                    Text("LATER").font(.system(size: 9, weight: .semibold)).tracking(2)
                    Text(model.laterText).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.55))
                .opacity(chromeVisible ? 1 : 0)
            }
            HStack(alignment: .bottom, spacing: 16) {
                Color.clear.frame(width: compact ? 36 : SpotifyControlView.tileSize, height: SpotifyControlView.tileSize)
                HStack(spacing: 0) {
                    Button { model.showsPicker = true } label: {
                        Label(compact ? "Task" : "Choose task", systemImage: "list.bullet")
                            .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    .help("Choose a task (⌘K)")
                    Divider().frame(height: 16).padding(.horizontal, 2)
                    Button(action: editFocus) {
                        Image(systemName: "square.and.pencil").frame(width: 40, height: 38)
                    }
                    .help("Write your own focus (⌘E)").accessibilityLabel("Write your own focus")
                    Button { model.completeCurrent() } label: {
                        Label(model.isCompleting ? "Finishing…" : "Done", systemImage: "checkmark")
                            .padding(.horizontal, 12).padding(.vertical, 11)
                    }
                    .disabled(current == nil || model.isCompleting)
                    .help(current?.source == .todoist ? "Complete this task in Todoist (⌘D)" : "Finish this focus (⌘D)")
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.10)))
                .opacity(chromeVisible ? 1 : 0)
                .accessibilityHidden(!chromeVisible)
                .onHover { controlsHovered = $0 }
                .frame(maxWidth: .infinity)
                // Reserve the tile's space; its hover panel lives in the full deck overlay.
                Color.clear.frame(width: SpotifyControlView.tileSize, height: SpotifyControlView.tileSize)
            }
        }
        .contentShape(Rectangle())
        .onHover { controlsHovered = $0 }
    }

    private var editSheet: some View {
        ZStack {
            Color.black.opacity(0.60).ignoresSafeArea().onTapGesture { if !model.isCreatingTask { model.isEditingFocus = false } }
            VStack(alignment: .leading, spacing: 18) {
                Text("What are you focusing on?").font(.system(size: 24, weight: .semibold))
                Text("Add your next task, or focus on it now.").foregroundStyle(.secondary)
                TextField("Type your focus", text: $model.draftTitle, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(2...4)
                    .padding(16)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .focused($editorFocused)
                    .disabled(model.isCreatingTask)
                if let error = model.draftError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TaskCreationActionsView(isCreating: model.isCreatingTask,
                    isDisabled: model.isCreatingTask || model.isCompleting || model.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    submit: { model.applyDraft(action: $0) },
                    cancel: { model.isEditingFocus = false })
            }
            .padding(28)
            .frame(maxWidth: 560)
            .background(Color(red: 0.085, green: 0.075, blue: 0.12), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
            .padding(24)
            .onAppear { editorFocused = true }
        }
    }

    private func editFocus() {
        guard !model.isCreatingTask else { return }
        model.draftError = nil
        model.draftTitle = current?.title ?? ""
        model.isEditingFocus = true
    }

    private func revealChrome() {
        showChrome = true
        chromeTask?.cancel()
        chromeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            showChrome = false
        }
    }

    static func durationLabel(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? String(format: "%dh %02dm", hours, minutes) : String(format: "%dm", minutes)
    }
}
