import XCTest
@testable import FocusDeckKit

final class SettingsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focusdeck-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A settings file from an older build has no `titleScrimStrength` (and no `startAtLogin`).
    func testOldSettingsFileStillLoads() throws {
        let old = """
        { "alwaysOnTop": false, "animationEnabled": true, "animationIntensity": 0.5,
          "backdropDarkness": 0.28, "nextDisplayShortcutEnabled": true, "paletteOverride": null,
          "showClock": true, "showCoverTitle": false, "showElapsed": true, "showQueue": true,
          "slideDuration": 0.9, "textScale": 1.6, "todoistEnabled": false,
          "todoistFilter": "today", "todoistRefreshMinutes": 5, "todoistTokenPresent": false,
          "uppercase": true }
        """
        let url = directory.appendingPathComponent("settings.json")
        try old.data(using: .utf8)!.write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.textScale, 1.6)
        XCTAssertEqual(store.settings.alwaysOnTop, false)
        XCTAssertEqual(store.settings.slideDuration, 0.9)
        // New fields fall back to the defaults instead of failing the whole file.
        XCTAssertEqual(store.settings.titleScrimStrength, FocusSettings().titleScrimStrength)
        XCTAssertEqual(store.settings.startAtLogin, false)
        XCTAssertEqual(store.settings.coverStyle, "gallery")
        XCTAssertFalse(store.settings.calendarEnabled)
        XCTAssertEqual(store.settings.calendarLeadMinutes, 10)
        XCTAssertNil(store.settings.selectedCalendarIDs)
        XCTAssertFalse(store.isFirstRun)
    }

    func testUnknownFieldsAreIgnored() throws {
        let url = directory.appendingPathComponent("settings.json")
        try #"{"textScale": 2.0, "somethingFromTheFuture": true}"#.data(using: .utf8)!.write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings.textScale, 2.0)
        XCTAssertEqual(store.settings.uppercase, FocusSettings().uppercase)
    }

    func testFirstRunIsReportedOnlyWhenThereIsNoFile() {
        let url = directory.appendingPathComponent("missing.json")
        XCTAssertTrue(SettingsStore(fileURL: url).isFirstRun)
    }

    func testRoundTripKeepsEveryField() throws {
        let url = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)
        store.settings.calendarEnabled = true
        store.settings.calendarLeadMinutes = 20
        store.settings.selectedCalendarIDs = ["example-calendar"]
        store.settings.textScale = 1.4
        store.settings.titleScrimStrength = 0.5
        store.settings.todoistFilter = "##Work"
        store.settings.coverStyle = "ocean"
        store.save()
        let reloaded = SettingsStore(fileURL: url)
        XCTAssertTrue(reloaded.settings.calendarEnabled)
        XCTAssertEqual(reloaded.settings.calendarLeadMinutes, 20)
        XCTAssertEqual(reloaded.settings.selectedCalendarIDs, ["example-calendar"])
        XCTAssertEqual(reloaded.settings.textScale, 1.4)
        XCTAssertEqual(reloaded.settings.titleScrimStrength, 0.5)
        XCTAssertEqual(reloaded.settings.todoistFilter, "##Work")
        XCTAssertEqual(reloaded.settings.coverStyle, "ocean")
        XCTAssertFalse(reloaded.isFirstRun)
    }
}
