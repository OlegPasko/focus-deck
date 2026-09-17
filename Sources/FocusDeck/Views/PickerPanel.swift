import SwiftUI
import FocusDeckKit

/// Pick deliberately: browsing and syncing never replace the task on the deck.
struct PickerPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: SettingsStore
    @State private var search = ""
    @SwiftUI.FocusState private var searchFocused: Bool

    init(model: AppModel) {
        self.model = model
        self._settings = ObservedObject(wrappedValue: model.settings)
    }

    private var visibleTasks: [TodoistTask] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.todoistTasks.filter {
            !$0.isCompleted && (query.isEmpty || $0.content.localizedCaseInsensitiveContains(query)
                || ($0.projectName?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.65).ignoresSafeArea().onTapGesture { model.showsPicker = false }
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Choose one thing").font(.system(size: 24, weight: .semibold))
                            Text("Everything else can wait.").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.showsPicker = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).keyboardShortcut(.escape, modifiers: []).accessibilityLabel("Close picker")
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search tasks or write a new focus", text: $search)
                            .textFieldStyle(.plain).focused($searchFocused)
                            .onSubmit {
                                if let first = visibleTasks.first { model.focus(on: first) }
                                else if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { useCustomText() }
                            }
                    }
                    .padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                    HStack(spacing: 7) {
                        filterButton("Today", query: "today | overdue")
                        filterButton("Upcoming", query: "7 days")
                        filterButton("All", query: "")
                        if !["today | overdue", "7 days", ""].contains(settings.settings.todoistFilter) {
                            Text("Custom filter").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if model.isSyncing { ProgressView().controlSize(.small) }
                        else {
                            Button { Task { await model.refreshTodoist() } } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).accessibilityLabel("Refresh tasks")
                        }
                    }

                    if let error = model.todoistError {
                        Text(error).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            if !settings.settings.todoistTokenPresent {
                                emptyMessage("Your tasks, one at a time", detail: "Connect Todoist to choose from your list, or write your own focus.")
                                Button("Connect Todoist") { model.showsPicker = false; model.showsSettings = true }
                                    .buttonStyle(.bordered)
                            } else if !settings.settings.todoistEnabled {
                                emptyMessage("Todoist sync is paused", detail: "Enable sync in Settings to load tasks.")
                                Button("Open Settings") { model.showsPicker = false; model.showsSettings = true }
                            } else if visibleTasks.isEmpty && !model.isSyncing {
                                emptyMessage(search.isEmpty ? "No tasks in this view" : "No matching tasks",
                                    detail: search.isEmpty ? "Try All, or write a focus above." : "Try another search, or use these words as your focus.")
                            }
                            ForEach(visibleTasks) { task in taskRow(task) }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    Divider().opacity(0.5)
                    HStack {
                        Text("Select a task to focus on it.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button(search.isEmpty ? "Write my own…" : "Use my text") {
                            if search.isEmpty {
                                model.draftTitle = ""; model.showsPicker = false; model.isEditingFocus = true
                            } else { useCustomText() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(height: min(650, max(260, geometry.size.height - 48)))
                .background(Color(red: 0.085, green: 0.075, blue: 0.12), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.refreshTodoist() }
        .onAppear { searchFocused = true }
    }

    private func filterButton(_ title: String, query: String) -> some View {
        Button { model.setTodoistFilter(query) } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(settings.settings.todoistFilter == query ? .white.opacity(0.15) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func taskRow(_ task: TodoistTask) -> some View {
        let current = model.store.state.current?.id == "todoist:\(task.id)"
        return Button { model.focus(on: task) } label: {
            HStack(spacing: 12) {
                Image(systemName: current ? "smallcircle.filled.circle" : "arrow.up.right")
                    .font(.system(size: 12)).foregroundStyle(current ? .pink : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.content).font(.system(size: 14, weight: .medium)).lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let project = task.projectName { Text(project) }
                        if let due = task.dueDate { Text(String(due.prefix(10))) }
                        if current { Text("Focusing now").foregroundStyle(.pink) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(current ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyMessage(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 16, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(.vertical, 20)
    }

    private func useCustomText() {
        model.draftTitle = search
        model.showsPicker = false
        model.isEditingFocus = true
        model.applyDraft()
    }
}
