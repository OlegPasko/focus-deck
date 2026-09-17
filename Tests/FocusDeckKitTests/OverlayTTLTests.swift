import XCTest
@testable import FocusDeckKit

final class OverlayTTLTests: XCTestCase {
    func testNonFiniteAndSillyTTLsBecomeTheDefault() {
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(.nan), 12)
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(.infinity), 12)
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(0), 12)
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(-5), 12)
    }

    func testClamping() {
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(0.1), 0.5)
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(99_999), 3600)
        XCTAssertEqual(FocusStore.sanitizedOverlayTTL(15), 15)
    }

    /// A banner with a NaN lifetime used to make the whole JSON write fail silently.
    func testNaNTTLStillWritesAValidFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focusdeck-ttl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("focus.json")
        let store = FocusStore(fileURL: url, writerName: "test")
        store.showOverlay(text: "boom", ttl: .nan)
        XCTAssertNil(store.lastError)
        let reloaded = FocusStore(fileURL: url, writerName: "test")
        XCTAssertEqual(reloaded.state.overlay?.ttl, 12)
        XCTAssertTrue(reloaded.state.overlay?.isAlive() ?? false)
    }
}
