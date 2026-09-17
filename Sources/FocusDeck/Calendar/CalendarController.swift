import AppKit
import Combine
import EventKit
import FocusDeckKit

struct CalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
}

struct MeetingEvent: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    var isAllDay = false
    var isCancelled = false
    var isDeclined = false

    func isUrgent(at now: Date) -> Bool { start.timeIntervalSince(now) <= 60 }

    func countdown(at now: Date) -> String {
        let seconds = max(0, Int(ceil(start.timeIntervalSince(now))))
        if seconds == 0 { return "Starting now" }
        return String(format: "In %d:%02d", seconds / 60, seconds % 60)
    }

    static func next(in events: [Self], now: Date, leadMinutes: Int) -> Self? {
        let lead = TimeInterval(min(120, max(1, leadMinutes)) * 60)
        return events.filter {
            !$0.isAllDay && !$0.isCancelled && !$0.isDeclined && $0.end > now &&
            $0.start > now.addingTimeInterval(-60) && $0.start <= now.addingTimeInterval(lead)
        }.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }.first
    }
}

enum CalendarAccess { case notDetermined, allowed, denied, restricted }

@MainActor
protocol CalendarReading {
    var access: CalendarAccess { get }
    func requestAccess() async throws -> Bool
    func calendars() -> [CalendarChoice]
    func events(from: Date, to: Date, calendarIDs: [String]?) -> [MeetingEvent]
}

@MainActor
final class SystemCalendarReader: CalendarReading {
    private lazy var store = EKEventStore()

    var access: CalendarAccess {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *), status == .fullAccess { return .allowed }
        switch status {
        case .authorized: return .allowed
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied
        }
    }

    func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) { return try await store.requestFullAccessToEvents() }
        return try await store.requestAccess(to: .event)
    }

    func calendars() -> [CalendarChoice] {
        store.calendars(for: .event).map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title)
        }.sorted { ($0.account, $0.title, $0.id) < ($1.account, $1.title, $1.id) }
    }

    func events(from: Date, to: Date, calendarIDs: [String]?) -> [MeetingEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs?.contains($0.calendarIdentifier) ?? true }
        // EventKit interprets an empty calendar list as all calendars in some queries.
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        return store.events(matching: predicate).map { event in
            MeetingEvent(id: event.calendarItemIdentifier, title: event.title ?? "Untitled event",
                         start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                         isCancelled: event.status == .canceled,
                         isDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
        }
    }
}

/// Reads calendar metadata only after the user connects in Settings. Nothing is written to Calendar.
@MainActor
final class CalendarController: ObservableObject {
    @Published private(set) var access: CalendarAccess = .notDetermined
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var events: [MeetingEvent] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var error: String?
    private let settings: SettingsStore
    private let reader: CalendarReading
    private var subscriptions: Set<AnyCancellable> = []
    private var lastRefresh = Date.distantPast
    private var started = false

    init(settings: SettingsStore, reader: CalendarReading? = nil) {
        self.settings = settings
        self.reader = reader ?? SystemCalendarReader()
    }

    func start() {
        guard !started else { return }
        started = true
        settings.$settings
            .map { CalendarPreferences(enabled: $0.calendarEnabled, lead: $0.calendarLeadMinutes, ids: $0.selectedCalendarIDs) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update(force: true) }
            .store(in: &subscriptions)
        for notification in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                             NSNotification.Name.NSSystemClockDidChange] {
            NotificationCenter.default.publisher(for: notification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.update(force: true) }
                .store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update(force: true) }
            .store(in: &subscriptions)
        update(force: true)
    }

    func update(now: Date = Date(), force: Bool = false) {
        guard force || now.timeIntervalSince(lastRefresh) >= 30 || now < lastRefresh else { return }
        lastRefresh = now
        access = reader.access
        guard settings.settings.calendarEnabled, access == .allowed else {
            events = []
            calendars = []
            return
        }
        calendars = reader.calendars()
        events = reader.events(from: now.addingTimeInterval(-60),
                               to: now.addingTimeInterval(TimeInterval(min(120, max(1, settings.settings.calendarLeadMinutes)) * 60 + 60)),
                               calendarIDs: settings.settings.selectedCalendarIDs)
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        do {
            let granted: Bool
            if reader.access == .allowed { granted = true }
            else if reader.access == .restricted { granted = false }
            else { granted = try await reader.requestAccess() }
            settings.settings.calendarEnabled = granted
            if !granted { error = "Calendar access is off. Allow access in System Settings → Privacy & Security → Calendars." }
        } catch {
            self.error = "Could not connect Calendar. Try again or check Calendar access in System Settings."
        }
        update(force: true)
    }

    func disconnect() {
        settings.settings.calendarEnabled = false
        events = []
        calendars = []
        error = nil
    }

    func reminder(at now: Date) -> MeetingEvent? {
        guard settings.settings.calendarEnabled, access == .allowed else { return nil }
        return MeetingEvent.next(in: events, now: now, leadMinutes: settings.settings.calendarLeadMinutes)
    }

    private struct CalendarPreferences: Equatable {
        let enabled: Bool
        let lead: Int
        let ids: [String]?
    }
}
