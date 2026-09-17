import Foundation
import SwiftUI
import Combine
import ServiceManagement
import FocusDeckKit

/// One place that holds the shared state, the settings and the Todoist connection.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store: FocusStore
    let settings: SettingsStore
    let spotify = SpotifyController()
    let calendar: CalendarController

    @Published var isEditingFocus = false
    @Published var draftTitle = ""
    @Published private(set) var isCreatingTask = false
    @Published var draftError: String?
    private var pendingCreation: (title: String, dueDate: String, requestID: UUID)?
    private let makeTodoistClient: () -> TodoistClient?
    @Published var showsSettings = false
    @Published var showsPicker = false
    @Published var todoistTasks: [TodoistTask] = []
    @Published var todoistMessage: String?
    @Published var isSyncing = false
    @Published var isCompleting = false
    @Published var todoistError: String?
    private var syncGeneration = 0
    @Published private(set) var todayTasks: [TodoistTask] = []
    @Published private(set) var todayLoaded = false
    @Published private(set) var todayError: String?
    @Published private(set) var isLoadingToday = false
    private var todayGeneration = 0
    private var advanceWhenTodayLoads = false

    var nextTodayTask: TodoistTask? {
        todayTasks.first { !$0.isCompleted && "todoist:\($0.id)" != store.state.current?.id }
    }

    var laterText: String {
        if todayError != nil { return "Could not load today’s tasks" }
        if !todayLoaded && !isLoadingToday && !settings.settings.todoistEnabled {
            return "Todoist sync is paused"
        }
        if isLoadingToday || !todayLoaded { return "Loading today’s tasks…" }
        return nextTodayTask?.content ?? "No more tasks for today"
    }

    var emptyFocusText: String {
        if todayError != nil { return "Could not load today’s tasks" }
        if isLoadingToday { return "Loading today’s tasks…" }
        if todayLoaded && todayTasks.isEmpty { return "No more tasks for today" }
        return "One thing\nat a time."
    }

    /// Ticks once a second so the clock, the time on task and the banner stay honest.
    @Published private(set) var now = Date()

    private var refreshTask: Task<Void, Never>?
    private var overlayClearTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(store: FocusStore = FocusStore(writerName: "app"),
         settings: SettingsStore = SettingsStore(), loadCredentials: Bool = true,
         makeTodoistClient: @escaping () -> TodoistClient? = { TodoistClient() }) {
        self.store = store
        self.settings = settings
        self.makeTodoistClient = makeTodoistClient
        self.calendar = CalendarController(settings: settings)
        if loadCredentials {
            self.settings.settings.todoistTokenPresent = KeychainStore.todoistToken != nil
        }
    }

    func start() {
        // Write the settings once per launch, so the file always shows every option the app uses.
        settings.save()
        startTicking()
        spotify.start()
        calendar.start()
        store.startWatching()
        scheduleTodoistRefresh()
        applyStartAtLogin(settings.settings.startAtLogin)
        if let problem = store.lastError {
            flash("The focus file needs attention", subtitle: problem, kind: "warn")
        }
        showFirstRunHint()
    }

    private func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.now = Date()
                    self.calendar.update(now: self.now)
                    self.store.clearExpiredOverlay(now: self.now)
                }
            }
        }
    }

    /// On the very first start, tell the user how to move the deck to another display.
    private func showFirstRunHint() {
        guard settings.isFirstRun, !didShowFirstRunHint else { return }
        didShowFirstRunHint = true
        let displays = NSScreen.screens.count
        if displays > 1 {
            flash("Press \u{2303}\u{2325}\u{2192} to move me to your second display", kind: "info")
        } else {
            flash("Type what you are doing now, then drag me to a free corner", kind: "info")
        }
    }

    private var didShowFirstRunHint = false

    // MARK: - Login item

    /// Register or unregister the app as a login item (macOS 13+).
    func applyStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("FocusDeck: login item change failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Focus commands

    @discardableResult
    func applyDraft() -> Task<Void, Never>? {
        guard !isCreatingTask, !isCompleting else { return nil }
        let text = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        draftError = nil
        if let current = store.state.current, current.source == .todoist, current.title == text {
            draftTitle = ""
            isEditingFocus = false
            return nil
        }
        guard let client = makeTodoistClient() else {
            draftError = "Connect Todoist in Settings to add this task to Today. Your draft is saved here."
            return nil
        }
        if pendingCreation?.title != text {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            pendingCreation = (text, formatter.string(from: Date()), UUID())
        }
        guard let pending = pendingCreation else { return nil }
        let expectedCurrentID = store.state.current?.id
        isCreatingTask = true
        return Task { [weak self] in
            guard let self else { return }
            defer { isCreatingTask = false }
            do {
                let task = try await client.createTask(content: pending.title, dueDate: pending.dueDate,
                                                       requestID: pending.requestID)
                store.adoptCreatedTask(task.asFocusItem(), expectedCurrentID: expectedCurrentID)
                todoistTasks.removeAll { $0.id == task.id }
                todoistTasks.insert(task, at: 0)
                todayTasks.removeAll { $0.id == task.id }
                todayTasks.insert(task, at: 0)
                pendingCreation = nil
                draftTitle = ""
                draftError = nil
                isEditingFocus = false
                showsPicker = false
            } catch {
                draftError = "Could not add this task to Todoist Today. " + error.localizedDescription
            }
        }
    }

    /// Finish the current task. For a Todoist task we ask Todoist first, and only move on
    /// when it agrees, so the deck and Todoist never disagree about what is still open.
    @discardableResult
    func completeCurrent() -> Task<Void, Never>? {
        guard !isCreatingTask, !isCompleting, let finished = store.state.current else { return nil }
        guard let client = makeTodoistClient() else {
            if finished.source != .todoist {
                store.completeCurrent(expectedID: finished.id)
                return nil
            }
            flash("Connect Todoist to complete this task", subtitle: "Your task is still open. Add the token in Settings.", kind: "warn")
            return nil
        }
        isCompleting = true
        return Task { [weak self] in
            guard let self else { return }
            defer { self.isCompleting = false }
            do {
                if finished.source == .todoist { try await client.complete(taskID: finished.id) }
                self.store.completeCurrent(expectedID: finished.id, advanceQueue: false)
                self.todoistTasks.removeAll { "todoist:\($0.id)" == finished.id }
                self.todayTasks.removeAll { "todoist:\($0.id)" == finished.id }
                self.advanceWhenTodayLoads = self.store.state.current == nil
                await self.refreshToday(excluding: finished.id)
            } catch {
                self.flash("Could not complete the Todoist task", subtitle: error.localizedDescription, kind: "warn")
            }
        }
    }

    func flash(_ text: String, subtitle: String? = nil, kind: String = "info") {
        store.showOverlay(text: text, subtitle: subtitle, kind: kind)
        let mine = store.state.overlay?.id
        overlayClearTask?.cancel()
        overlayClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Only remove our own banner: an agent may have replaced it meanwhile.
                guard let self, self.store.state.overlay?.id == mine else { return }
                self.store.clearOverlay()
            }
        }
    }

    // MARK: - Todoist

    func saveTodoistToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard KeychainStore.deleteSecret(account: KeychainStore.todoistAccount) else {
                todoistMessage = "Could not remove the token from Keychain."
                return
            }
            syncGeneration += 1
            refreshTask?.cancel()
            isSyncing = false
            todoistTasks = []
            todayGeneration += 1
            todayTasks = []
            todayLoaded = false
            todayError = nil
            isLoadingToday = false
            advanceWhenTodayLoads = false
            todoistError = nil
            settings.settings.todoistTokenPresent = false
            settings.settings.todoistEnabled = false
            todoistMessage = "Todoist token removed."
            return
        }
        let stored = KeychainStore.setSecret(trimmed, account: KeychainStore.todoistAccount)
        guard stored else {
            settings.settings.todoistTokenPresent = KeychainStore.todoistToken != nil
            todoistMessage = "The keychain refused to store the new token."
            flash("Could not save the Todoist token", subtitle: "The macOS keychain refused it.", kind: "warn")
            return
        }
        settings.settings.todoistTokenPresent = true
        settings.settings.todoistEnabled = true
        todoistMessage = "Token saved."
        scheduleTodoistRefresh()
    }

    func scheduleTodoistRefresh() {
        refreshTask?.cancel()
        syncGeneration += 1
        todayGeneration += 1
        isLoadingToday = false
        isSyncing = false
        guard settings.settings.todoistEnabled, settings.settings.todoistTokenPresent else { return }
        let minutes = max(0.5, settings.settings.todoistRefreshMinutes)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshTodoist()
                try? await Task.sleep(nanoseconds: UInt64(minutes * 60 * 1_000_000_000))
            }
        }
    }

    func refreshTodoist() async {
        guard settings.settings.todoistEnabled, !isSyncing else { return }
        guard let client = makeTodoistClient() else {
            todoistMessage = "No Todoist token yet. Paste it in Settings."
            return
        }
        isSyncing = true
        todoistError = nil
        let generation = syncGeneration
        let filter = settings.settings.todoistFilter
        defer { if generation == syncGeneration { isSyncing = false } }
        await refreshToday()
        guard !Task.isCancelled, generation == syncGeneration else { return }
        do {
            let tasks = try await client.tasks(filter: filter)
            let projects = (try? await client.projects()) ?? []
            guard !Task.isCancelled, generation == syncGeneration else { return }
            let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            todoistTasks = tasks.map { task in
                var copy = task
                if let id = task.projectID, let name = names[id] { copy.projectName = name }
                return copy
            }
            todoistMessage = "\(todoistTasks.count) task(s) from Todoist"
            // Picker results never populate the local queue or replace a chosen focus.
        } catch {
            guard !Task.isCancelled, generation == syncGeneration else { return }
            todoistError = error.localizedDescription
            todoistMessage = todoistError
        }
    }

    /// Today is independent of the picker filter. Preserve Todoist's returned order.
    func refreshToday(excluding finishedID: String? = nil) async {
        guard let client = makeTodoistClient() else { return }
        todayGeneration += 1
        let generation = todayGeneration
        let connectionGeneration = syncGeneration
        isLoadingToday = true
        todayError = nil
        defer { if generation == todayGeneration { isLoadingToday = false } }
        do {
            let tasks = try await client.tasks(filter: "today")
            guard !Task.isCancelled, generation == todayGeneration,
                  connectionGeneration == syncGeneration else { return }
            todayTasks = tasks.filter { !$0.isCompleted && "todoist:\($0.id)" != finishedID }
            todayLoaded = true
            if advanceWhenTodayLoads {
                let next = todayTasks.first?.asFocusItem()
                store.mutate { draft in
                    guard draft.current == nil else { return }
                    draft.current = next
                    if let next { draft.queue.removeAll { $0.id == next.id } }
                }
                advanceWhenTodayLoads = false
            }
        } catch {
            guard !Task.isCancelled, generation == todayGeneration,
                  connectionGeneration == syncGeneration else { return }
            todayError = error.localizedDescription
        }
    }

    func setTodoistFilter(_ filter: String) {
        settings.settings.todoistFilter = filter
        todoistTasks = []
        scheduleTodoistRefresh()
    }

    func focus(on task: TodoistTask) {
        store.setFocus(title: task.content, source: .todoist, project: task.projectName,
                       detail: task.description, itemID: "todoist:\(task.id)")
        showsPicker = false
    }
}
