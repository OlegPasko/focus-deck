import XCTest
@testable import FocusDeckKit

/// The deck is written by the app, the CLI and any number of agents. These tests pin down
/// what happens when they write at the same time or write a partial file.
final class MultiWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focusdeck-multi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var stateURL: URL { directory.appendingPathComponent("focus.json") }

    // MARK: - Partial files written by hand

    func testItemWithoutCoverSeedStillDecodes() throws {
        let json = """
        {"revision": 3, "writer": "agent", "updatedAt": "2026-09-15T09:00:00Z",
         "current": {"id": "abc", "title": "Written by an agent script", "source": "agent"},
         "queue": [], "history": []}
        """
        try json.data(using: .utf8)!.write(to: stateURL)
        let state = FocusStore.readState(at: stateURL)
        XCTAssertNotNil(state, "a state file without coverSeed must still load")
        XCTAssertEqual(state?.current?.title, "Written by an agent script")
        XCTAssertEqual(state?.current?.coverSeed, CoverCatalog.seed(from: "Written by an agent script"))
    }

    func testMinimalStateFileLoads() throws {
        try #"{"current": {"title": "Only a title"}}"#.data(using: .utf8)!.write(to: stateURL)
        let store = FocusStore(fileURL: stateURL, writerName: "test")
        XCTAssertEqual(store.state.current?.title, "Only a title")
        XCTAssertNil(store.lastError)
    }

    func testGarbageFileIsQuarantinedAndTheDeckStillWorks() throws {
        try Data().write(to: stateURL)                       // truncated by a crash
        let store = FocusStore(fileURL: stateURL, writerName: "test")
        XCTAssertNil(store.state.current)
        XCTAssertNotNil(store.lastError, "the user must be told something was wrong")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("corrupt") }
        XCTAssertEqual(backups.count, 1, "the unreadable file is kept, not deleted")
        store.setFocus(title: "Still usable")
        XCTAssertEqual(FocusStore.readState(at: stateURL)?.current?.title, "Still usable")
    }

    // MARK: - Two writers at the same time

    func testConcurrentWritersDoNotLoseUpdates() throws {
        // Two stores (like the app and the CLI) writing different fields at once.
        let first = FocusStore(fileURL: stateURL, writerName: "app")
        let second = FocusStore(fileURL: stateURL, writerName: "cli")

        let group = DispatchGroup()
        let rounds = 25
        // Each writer submits in order; the two writers still run concurrently.
        // A global concurrent queue does not guarantee that index 24 writes last.
        let appQueue = DispatchQueue(label: "test.app-writer")
        let cliQueue = DispatchQueue(label: "test.cli-writer")
        for index in 0..<rounds {
            appQueue.async(group: group) {
                first.mutate { $0.overlay = OverlayMessage(text: "app-\(index)") }
            }
            cliQueue.async(group: group) {
                second.mutate { $0.queue = [FocusItem(title: "cli-\(index)")] }
            }
        }
        group.wait()

        let final = FocusStore.readState(at: stateURL)
        XCTAssertNotNil(final)
        XCTAssertGreaterThanOrEqual(final?.revision ?? 0, rounds * 2,
                                    "every write must advance the revision")
        // The last writes from both sides survive; nothing was silently dropped.
        XCTAssertEqual(final?.overlay?.text, "app-\(rounds - 1)")
        XCTAssertEqual(final?.queue.first?.title, "cli-\(rounds - 1)")
    }

    func testWriteIsAtomicSoReadersNeverSeeAPartialFile() throws {
        let writer = FocusStore(fileURL: stateURL, writerName: "app")
        writer.setFocus(title: "Start")
        let group = DispatchGroup()
        for index in 0..<40 {
            DispatchQueue.global().async(group: group) {
                writer.mutate { $0.current = FocusItem(title: "Value \(index)") }
            }
            DispatchQueue.global().async(group: group) {
                // A reader that only ever sees valid JSON.
                if let state = FocusStore.readState(at: self.stateURL) {
                    XCTAssertNotNil(state.current?.title)
                } else {
                    XCTFail("read a partial state file")
                }
            }
        }
        group.wait()
    }

    /// Another writer may produce the same revision number; the app must still notice.
    func testEqualRevisionButDifferentContentIsAdopted() throws {
        let app = FocusStore(fileURL: stateURL, writerName: "app")
        app.setFocus(title: "First")
        let revision = app.state.revision

        var forged = app.state
        forged.current = FocusItem(title: "Second writer, same revision")
        forged.revision = revision
        try JSONCoding.encoder().encode(forged).write(to: stateURL)

        app.checkForExternalChange()
        XCTAssertEqual(app.state.current?.title, "Second writer, same revision")
    }

    /// A write failure must be visible instead of being swallowed.
    func testUnwritableStateFileReportsAnError() throws {
        let readOnlyDirectory = directory.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readOnlyDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnlyDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: readOnlyDirectory.path) }
        let store = FocusStore(fileURL: readOnlyDirectory.appendingPathComponent("focus.json"), writerName: "test")
        store.setFocus(title: "Should not be writable")
        XCTAssertNotNil(store.lastError)
    }
}
