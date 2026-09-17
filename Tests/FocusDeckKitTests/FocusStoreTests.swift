import XCTest
@testable import FocusDeckKit

final class FocusStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focusdeck-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSetFocusPersists() {
        let url = directory.appendingPathComponent("focus.json")
        let store = FocusStore(fileURL: url, writerName: "test")
        store.setFocus(title: "Write the design doc")
        let reloaded = FocusStore(fileURL: url, writerName: "test")
        XCTAssertEqual(reloaded.state.current?.title, "Write the design doc")
        XCTAssertGreaterThan(reloaded.state.revision, 0)
    }

    func testCompleteCurrentMovesQueue() {
        let url = directory.appendingPathComponent("focus.json")
        let store = FocusStore(fileURL: url, writerName: "test")
        store.setQueue([FocusItem(title: "Second"), FocusItem(title: "Third")])
        store.setFocus(title: "First")
        let next = store.completeCurrent()
        XCTAssertEqual(next?.title, "Second")
        XCTAssertEqual(store.state.current?.title, "Second")
        XCTAssertEqual(store.state.history.first?.title, "First")
    }

    func testExternalChangeIsPickedUp() throws {
        let url = directory.appendingPathComponent("focus.json")
        let store = FocusStore(fileURL: url, writerName: "app")
        store.setFocus(title: "Original")
        let other = FocusStore(fileURL: url, writerName: "cli")
        other.setFocus(title: "Changed by the CLI")
        store.checkForExternalChange()
        XCTAssertEqual(store.state.current?.title, "Changed by the CLI")
    }

    func testDelayedCompletionDoesNotFinishAnotherWritersTask() {
        let url = directory.appendingPathComponent("focus.json")
        let app = FocusStore(fileURL: url, writerName: "app")
        app.setFocus(title: "Original", itemID: "todoist:original")
        let agent = FocusStore(fileURL: url, writerName: "agent")
        agent.setFocus(title: "New focus", itemID: "new")
        app.completeCurrent(expectedID: "todoist:original")
        XCTAssertEqual(app.state.current?.id, "new")
        XCTAssertFalse(app.state.history.contains { $0.id == "new" })
    }

    func testQueuedTaskTimerStartsWhenPromoted() {
        let url = directory.appendingPathComponent("focus.json")
        let store = FocusStore(fileURL: url, writerName: "app")
        store.setFocus(title: "First")
        store.setQueue([FocusItem(title: "Next", startedAt: Date(timeIntervalSince1970: 0))])
        let before = Date()
        store.completeCurrent()
        XCTAssertGreaterThanOrEqual(store.state.current!.startedAt!, before)
    }

    func testExpiredOverlayIsCleared() {
        let url = directory.appendingPathComponent("focus.json")
        let store = FocusStore(fileURL: url, writerName: "test")
        store.showOverlay(text: "hello", ttl: 5)
        XCTAssertNotNil(store.activeOverlay(at: Date()))
        XCTAssertNotNil(store.activeOverlay(at: Date().addingTimeInterval(3)))
        XCTAssertNil(store.activeOverlay(at: Date().addingTimeInterval(30)))
        // Time passes: the store drops the banner itself.
        store.mutate { $0.overlay?.createdAt = Date().addingTimeInterval(-60) }
        XCTAssertTrue(store.clearExpiredOverlay())
        XCTAssertNil(store.state.overlay)
        XCTAssertFalse(store.clearExpiredOverlay())
    }

    func testOverlayExpires() {
        let overlay = OverlayMessage(text: "hello", createdAt: Date().addingTimeInterval(-10), ttl: 5)
        XCTAssertFalse(overlay.isAlive())
        XCTAssertTrue(OverlayMessage(text: "hi", ttl: 5).isAlive())
    }
}
