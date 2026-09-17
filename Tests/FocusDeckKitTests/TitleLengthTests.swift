import XCTest
@testable import FocusDeckKit

final class TitleLengthTests: XCTestCase {
    func testShortTitleIsUntouched() {
        let split = FocusItem.splitTitle("Ship the app")
        XCTAssertEqual(split.title, "Ship the app")
        XCTAssertNil(split.remainder)
    }

    /// A pasted URL or hash must not be drawn at 60 pt across the whole window.
    func testLongTitleIsSplit() {
        let long = String(repeating: "L", count: 620)
        let split = FocusItem.splitTitle(long)
        XCTAssertEqual(split.title.count, FocusItem.maxTitleLength + 1)   // + the ellipsis
        XCTAssertTrue(split.title.hasSuffix("\u{2026}"))
        XCTAssertEqual(split.remainder?.count, 620 - FocusItem.maxTitleLength)
    }

    func testItemKeepsTheRemainderAsDetail() {
        let long = String(repeating: "word ", count: 100)
        let item = FocusItem(title: long)
        XCTAssertLessThanOrEqual(item.title.count, FocusItem.maxTitleLength + 1)
        XCTAssertNotNil(item.detail)
        XCTAssertLessThan(item.coverSeed, UInt64.max)
    }

    /// The last line of defence for drawing: the floor may lift a small fit, but not wildly.
    func testFloorDoesNotBlowUpAnImpossibleFit() {
        let longWord = String(repeating: "W", count: 400)
        let size = CGSize(width: 1200, height: 680)
        let font = TitleFitter.fontSize(for: longWord, in: size)
        XCTAssertLessThan(font, 200, "a word that cannot fit must not be drawn at the maximum size")
        let rawFit = TitleFitter.rawFit(for: longWord, in: size)
        XCTAssertLessThanOrEqual(font, max(rawFit * 2, TitleFitter.absoluteFloor) + 0.001)
    }
}
