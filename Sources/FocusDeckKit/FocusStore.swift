import Foundation
import Combine
import Darwin

/// Shared focus state. The app and the CLI both talk to one JSON file, so any tool
/// (including other agents) can change what the deck shows.
public final class FocusStore: ObservableObject {

    @Published public private(set) var state: FocusState
    @Published public private(set) var lastError: String?

    public let fileURL: URL
    private var watchedModificationDate: Date?
    private var timer: Timer?
    private var lastSelfWrite: Date = .distantPast
    private let writerName: String

    public init(fileURL: URL = FocusPaths.stateURL, writerName: String = "app") {
        self.fileURL = fileURL
        self.writerName = writerName
        FocusPaths.ensureDirectory()
        let loaded = FocusStore.loadOrQuarantine(at: fileURL)
        self.state = loaded.state
        self.lastError = loaded.message
        self.watchedModificationDate = FocusStore.modificationDate(at: fileURL)
    }

    /// Read the state file, or move an unreadable one aside so the deck still works.
    /// A truncated file used to leave the deck blank with no trace of what happened.
    static func loadOrQuarantine(at url: URL) -> (state: FocusState, message: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (FocusState.empty(), nil)
        }
        if let loaded = readState(at: url) { return (loaded, nil) }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: backup)
        let message = "focus.json could not be read; a copy was kept at \(backup.lastPathComponent)"
        NSLog("FocusDeck: %@", message)
        return (FocusState.empty(), message)
    }

    /// Cross-process lock around a read-modify-write of the state file.
    /// Several agents may write at the same time; without this, updates get lost.
    static func withFileLock<T>(_ url: URL, _ body: () -> T) -> T {
        let lockPath = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return body() }
        defer { close(descriptor) }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }

    // MARK: - Reading / writing

    public static func readState(at url: URL) -> FocusState? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONCoding.decoder().decode(FocusState.self, from: data)
    }

    public static func modificationDate(at url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Write the state to disk with a bumped revision.
    public func save() {
        mutate { _ in }
    }

    private func writeToDisk(_ value: FocusState) {
        FocusPaths.ensureDirectory()
        // Guard the one field that a caller can fill with a non-finite number.
        var value = value
        if var overlay = value.overlay, !overlay.ttl.isFinite || overlay.ttl <= 0 {
            overlay.ttl = 12
            value.overlay = overlay
        }
        // A per-process temp name: two writers sharing one temp path lose data.
        let temporary = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".focus-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).tmp")
        do {
            let data = try JSONCoding.encoder().encode(value)
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
            lastSelfWrite = Date()
            watchedModificationDate = FocusStore.modificationDate(at: fileURL)
            lastError = nil
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            let message = "Cannot write focus state: \(error.localizedDescription)"
            lastError = message
            NSLog("FocusDeck: %@", message)
        }
    }

    /// Apply a change and persist it under a cross-process lock.
    ///
    /// The file, not our memory, is the starting point: that way a change made by another
    /// agent in the meantime is kept instead of being overwritten.
    public func mutate(_ body: (inout FocusState) -> Void) {
        let knownRevision = state.revision
        let merged = FocusStore.withFileLock(fileURL) { () -> FocusState in
            var draft = FocusStore.readState(at: fileURL) ?? state
            body(&draft)
            draft.revision = max(draft.revision, knownRevision) + 1
            draft.writer = writerName
            draft.updatedAt = Date()
            writeToDisk(draft)
            return draft
        }
        state = merged
    }

    // MARK: - Focus commands

    public func setFocus(title: String, source: TaskSource = .custom, project: String? = nil,
                         detail: String? = nil, itemID: String? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { draft in
            if let previous = draft.current, previous.title != trimmed {
                var archived = previous
                if archived.startedAt == nil { archived.startedAt = Date() }
                draft.history.insert(archived, at: 0)
                draft.history = Array(draft.history.prefix(50))
            }
            let item = FocusItem(id: itemID ?? UUID().uuidString, title: trimmed, source: source,
                                 project: project, detail: detail, startedAt: Date())
            draft.current = item
            draft.queue.removeAll { $0.id == item.id }
        }
    }

    /// Adopt a remote creation without overwriting a focus changed by another writer while awaiting the API.
    public func adoptCreatedTask(_ item: FocusItem, expectedCurrentID: String?) {
        mutate { draft in
            if draft.current?.id == item.id { return }
            draft.queue.removeAll { $0.id == item.id }
            guard draft.current?.id == expectedCurrentID else {
                var queued = item
                queued.startedAt = nil
                draft.queue.append(queued)
                return
            }
            if let previous = draft.current {
                draft.history.insert(previous, at: 0)
                draft.history = Array(draft.history.prefix(50))
            }
            draft.current = item
        }
    }

    /// Mark the current item done and move to the next queued item, if any.
    /// Pass advanceQueue: false when the caller will select a fresh Todoist task.
    @discardableResult
    public func completeCurrent(expectedID: String? = nil, advanceQueue: Bool = true) -> FocusItem? {
        var nextUp: FocusItem?
        mutate { draft in
            guard expectedID == nil || draft.current?.id == expectedID else { return }
            if let finished = draft.current {
                draft.history.insert(finished, at: 0)
                draft.history = Array(draft.history.prefix(50))
            }
            nextUp = advanceQueue ? draft.queue.first : nil
            nextUp?.startedAt = Date()
            draft.current = nextUp
            if nextUp != nil { draft.queue.removeFirst() }
        }
        return nextUp
    }

    public func setQueue(_ items: [FocusItem]) {
        mutate { draft in
            draft.queue = items.filter { $0.id != draft.current?.id }
        }
    }

    /// Shortest and longest banner lifetime we accept, in seconds.
    public static let overlayTTLRange: ClosedRange<TimeInterval> = 0.5...3600

    /// Turn any input into a banner lifetime that is safe to store.
    /// `nan`, `inf` and silly values used to make the JSON write fail silently.
    public static func sanitizedOverlayTTL(_ ttl: TimeInterval) -> TimeInterval {
        guard ttl.isFinite, ttl > 0 else { return 12 }
        return min(max(ttl, overlayTTLRange.lowerBound), overlayTTLRange.upperBound)
    }

    public func showOverlay(text: String, subtitle: String? = nil, kind: String = "info", ttl: TimeInterval = 12) {
        let safeTTL = FocusStore.sanitizedOverlayTTL(ttl)
        mutate { draft in
            draft.overlay = OverlayMessage(text: text, subtitle: subtitle, kind: kind, ttl: safeTTL)
        }
    }

    public func clearOverlay() {
        mutate { draft in draft.overlay = nil }
    }

    /// Live overlay, if it has not expired yet.
    public var activeOverlay: OverlayMessage? { activeOverlay(at: Date()) }

    public func activeOverlay(at moment: Date) -> OverlayMessage? {
        guard let overlay = state.overlay, overlay.isAlive(now: moment) else { return nil }
        return overlay
    }

    /// Drop the banner once its time to live is over. Returns true when it was cleared.
    @discardableResult
    public func clearExpiredOverlay(now: Date = Date()) -> Bool {
        guard let overlay = state.overlay, !overlay.isAlive(now: now) else { return false }
        mutate { $0.overlay = nil }
        return true
    }

    // MARK: - Watching the file for outside changes

    /// Start polling the state file. Another process (CLI or agent) can then change the deck.
    public func startWatching(interval: TimeInterval = 1.0) {
        stopWatching()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForExternalChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    public func checkForExternalChange() {
        guard let stamp = FocusStore.modificationDate(at: fileURL) else { return }
        if let known = watchedModificationDate, stamp <= known { return }
        watchedModificationDate = stamp
        guard let fresh = FocusStore.readState(at: fileURL) else { return }
        // Adopt any real difference. Comparing only the revision missed a second writer
        // that happened to land on the same revision number.
        if fresh != state {
            state = fresh
            lastError = nil
        }
    }
}
