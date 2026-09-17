import XCTest
import FocusDeckKit
@testable import FocusDeck

final class CalendarTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(_ offset: TimeInterval, id: String = "meeting") -> MeetingEvent {
        MeetingEvent(id: id, title: "Design review", start: now.addingTimeInterval(offset),
                     end: now.addingTimeInterval(offset + 1800))
    }

    func testLeadTimeAndUrgencyBoundaries() {
        XCTAssertNil(MeetingEvent.next(in: [meeting(601)], now: now, leadMinutes: 10))
        XCTAssertEqual(MeetingEvent.next(in: [meeting(600)], now: now, leadMinutes: 10), meeting(600))
        XCTAssertNil(MeetingEvent.next(in: [meeting(600)], now: now, leadMinutes: 5))
        XCTAssertNotNil(MeetingEvent.next(in: [meeting(1200)], now: now, leadMinutes: 20))
        XCTAssertFalse(meeting(61).isUrgent(at: now))
        XCTAssertTrue(meeting(60).isUrgent(at: now))
        XCTAssertEqual(meeting(600).countdown(at: now), "In 10:00")
        XCTAssertEqual(meeting(59.1).countdown(at: now), "In 1:00")
        XCTAssertEqual(meeting(1).countdown(at: now), "In 0:01")
        XCTAssertEqual(meeting(0).countdown(at: now), "Starting now")
    }

    func testSkipNonMeetingsAndChooseEarliestRegardlessOfInputOrder() {
        var allDay = meeting(5); allDay.isAllDay = true
        var cancelled = meeting(10); cancelled.isCancelled = true
        var declined = meeting(15); declined.isDeclined = true
        var ended = meeting(-1); ended = MeetingEvent(id: "ended", title: "Ended", start: ended.start, end: now)
        let next = MeetingEvent.next(in: [meeting(400), allDay, cancelled, declined, ended, meeting(100, id: "first")], now: now, leadMinutes: 10)
        XCTAssertEqual(next?.id, "first")
    }

    func testStartGracePeriodAndConsecutiveMeetings() {
        XCTAssertNotNil(MeetingEvent.next(in: [meeting(-59)], now: now, leadMinutes: 10))
        XCTAssertNil(MeetingEvent.next(in: [meeting(-60)], now: now, leadMinutes: 10))
        XCTAssertEqual(MeetingEvent.next(in: [meeting(-60), meeting(10, id: "next")], now: now, leadMinutes: 10)?.id, "next")
    }

    @MainActor
    func testConnectionSelectionRefreshRevocationAndDisconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let reader = FakeCalendarReader()
        reader.items = [meeting(300)]
        let controller = CalendarController(settings: settings, reader: reader)
        controller.update(now: now, force: true)
        XCTAssertEqual(reader.requests, 0, "Opening the app must not prompt for Calendar access")
        XCTAssertEqual(reader.reads, 0)
        await controller.connect()
        XCTAssertEqual(reader.requests, 1)
        XCTAssertTrue(settings.settings.calendarEnabled)
        controller.update(now: now, force: true)
        XCTAssertEqual(controller.reminder(at: now)?.title, "Design review")
        settings.settings.selectedCalendarIDs = ["work"]
        controller.update(now: now, force: true)
        XCTAssertEqual(reader.lastIDs, ["work"])
        settings.settings.selectedCalendarIDs = []
        controller.update(now: now, force: true)
        XCTAssertNil(controller.reminder(at: now))
        reader.access = .denied
        controller.update(now: now, force: true)
        XCTAssertTrue(controller.events.isEmpty)
        XCTAssertTrue(controller.calendars.isEmpty)
        XCTAssertNil(controller.reminder(at: now))
        controller.disconnect()
        XCTAssertFalse(settings.settings.calendarEnabled)
    }

    @MainActor
    func testDeniedAccessDoesNotReadCalendars() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let reader = FakeCalendarReader()
        reader.grantsAccess = false
        let controller = CalendarController(settings: settings, reader: reader)
        await controller.connect()
        XCTAssertFalse(settings.settings.calendarEnabled)
        XCTAssertNotNil(controller.error)
        XCTAssertEqual(reader.reads, 0)
        XCTAssertTrue(controller.events.isEmpty)
    }
}

@MainActor
private final class FakeCalendarReader: CalendarReading {
    var access: CalendarAccess = .notDetermined
    var grantsAccess = true
    var requests = 0
    var reads = 0
    var lastIDs: [String]?
    var items: [MeetingEvent] = []
    func requestAccess() async throws -> Bool {
        requests += 1
        access = grantsAccess ? .allowed : .denied
        return grantsAccess
    }
    func calendars() -> [CalendarChoice] {
        [CalendarChoice(id: "work", title: "Work", account: "Example")]
    }
    func events(from: Date, to: Date, calendarIDs: [String]?) -> [MeetingEvent] {
        reads += 1
        lastIDs = calendarIDs
        return calendarIDs == [] ? [] : items
    }
}
