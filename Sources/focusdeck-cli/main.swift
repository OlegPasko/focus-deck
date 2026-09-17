import Foundation
import FocusDeckKit

// focusdeck - tiny command line bridge for the Focus Deck window.
// Any agent or script can use it to change what the deck shows right now.

let arguments = Array(CommandLine.arguments.dropFirst())

func usage() {
    print("""
    focusdeck - control the Focus Deck window

    USAGE:
      focusdeck set "<text>" [--project NAME] [--source custom|agent|todoist] [--detail TEXT]
      focusdeck overlay "<text>" [--subtitle TEXT] [--kind info|warn|agent] [--ttl SECONDS]
      focusdeck add "<task text>"    add the task to Todoist (Quick Add, needs a token)
      focusdeck queue "<text>" ["<text>" ...]
      focusdeck next                 move to the first queued task
      focusdeck done                 finish the current task and move on
      focusdeck clear                clear the current task
      focusdeck status [--json]      show the current task
      focusdeck path                 show the shared state file path

    The app watches the state file, so changes show up in under a second.
    """)
}

func value(for flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

/// Report a failed write and exit non-zero, instead of printing success into the void.
func requireWriteSuccess(_ store: FocusStore) {
    if let error = store.lastError {
        FileHandle.standardError.write(Data(("focusdeck: " + error + "\n").utf8))
        exit(2)
    }
}

func positional(_ args: [String]) -> [String] {
    var result: [String] = []
    var skipNext = false
    for (index, item) in args.enumerated() {
        if skipNext { skipNext = false; continue }
        if item.hasPrefix("--") {
            if ["--project", "--source", "--detail", "--subtitle", "--kind", "--ttl"].contains(item) {
                skipNext = true
            }
            continue
        }
        _ = index
        result.append(item)
    }
    return result
}

let store = FocusStore(writerName: "cli")

guard let command = arguments.first else {
    usage()
    exit(1)
}

switch command {
case "set":
    // `focusdeck set Ship the app` is a common slip: join the words instead of dropping them.
    let words = positional(Array(arguments.dropFirst()))
    let joined = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !joined.isEmpty else { usage(); exit(1) }
    let text = joined
    let rawSource = value(for: "--source", in: arguments)
    if let rawSource, TaskSource(rawValue: rawSource) == nil {
        FileHandle.standardError.write(Data("focusdeck: unknown --source \(rawSource), using custom\n".utf8))
    }
    let source = TaskSource(rawValue: rawSource ?? "custom") ?? .custom
    store.setFocus(title: text, source: source,
                   project: value(for: "--project", in: arguments),
                   detail: value(for: "--detail", in: arguments))
    requireWriteSuccess(store)
    print("focus: \(text)")

case "overlay":
    let words = positional(Array(arguments.dropFirst()))
    guard let text = words.first else { usage(); exit(1) }
    let rawTTL = value(for: "--ttl", in: arguments)
    let parsedTTL = rawTTL.flatMap(Double.init)
    if let rawTTL, parsedTTL == nil || !(parsedTTL ?? 0).isFinite || (parsedTTL ?? 0) <= 0 {
        FileHandle.standardError.write(Data("focusdeck: bad --ttl \(rawTTL), using 12 seconds\n".utf8))
    }
    let ttl = FocusStore.sanitizedOverlayTTL(parsedTTL ?? 12)
    store.showOverlay(text: text, subtitle: value(for: "--subtitle", in: arguments),
                      kind: value(for: "--kind", in: arguments) ?? "info", ttl: ttl)
    requireWriteSuccess(store)
    print("overlay: \(text) (ttl \(ttl)s)")

case "add":
    // Quick Add: put a task into Todoist without leaving the terminal.
    let words = positional(Array(arguments.dropFirst()))
    let text = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { usage(); exit(1) }
    guard let token = KeychainStore.todoistToken else {
        FileHandle.standardError.write(Data("focusdeck: no Todoist token yet. Add one in Focus Deck settings (Cmd ,).\n".utf8))
        exit(3)
    }
    let client = TodoistClient(token: token)
    var outcome: Result<TodoistTask?, Error> = .success(nil)
    let finished = DispatchSemaphore(value: 0)
    Task {
        do { outcome = .success(try await client.quickAdd(content: text)) }
        catch { outcome = .failure(error) }
        finished.signal()
    }
    finished.wait()
    switch outcome {
    case let .success(task):
        print("added: \(task?.content ?? text)")
    case let .failure(error):
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        FileHandle.standardError.write(Data("focusdeck: \(reason)\n".utf8))
        exit(2)
    }

case "queue":
    let titles = positional(Array(arguments.dropFirst()))
    if titles.isEmpty {
        FileHandle.standardError.write(Data("focusdeck: queue needs at least one task\n".utf8))
        exit(1)
    }
    let items = titles.map { FocusItem(title: $0) }
    store.setQueue(items)
    requireWriteSuccess(store)
    print("queue: \(items.count) item(s)")

case "next":
    let next = store.completeCurrent()
    requireWriteSuccess(store)
    print(next.map { "focus: \($0.title)" } ?? "queue is empty")

case "done":
    let next = store.completeCurrent()
    requireWriteSuccess(store)
    print(next.map { "focus: \($0.title)" } ?? "queue is empty")

case "clear":
    store.mutate { $0.current = nil }
    requireWriteSuccess(store)
    print("cleared")

case "status":
    if arguments.contains("--json") {
        let data = try JSONCoding.encoder().encode(store.state)
        print(String(data: data, encoding: .utf8) ?? "{}")
    } else {
        print("current: \(store.state.current?.title ?? "-")")
        print("queue:   \(store.state.queue.map(\.title).joined(separator: " | "))")
        print("file:    \(store.fileURL.path)")
    }

case "path":
    print(store.fileURL.path)

case "-h", "--help", "help":
    usage()

default:
    usage()
    exit(1)
}
