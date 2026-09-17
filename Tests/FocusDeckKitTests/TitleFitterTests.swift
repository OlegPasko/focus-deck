import XCTest
@testable import FocusDeckKit

final class TitleFitterTests: XCTestCase {
    func testLongerTextGetsSmallerFont() {
        let size = CGSize(width: 1200, height: 600)
        let short = TitleFitter.fontSize(for: "Focus", in: size)
        let long = TitleFitter.fontSize(for: String(repeating: "longer words here ", count: 8), in: size)
        XCTAssertGreaterThan(short, long)
    }

    func testFontGrowsWithWindow() {
        let small = TitleFitter.fontSize(for: "Ship it", in: CGSize(width: 500, height: 300))
        let large = TitleFitter.fontSize(for: "Ship it", in: CGSize(width: 2000, height: 1000))
        XCTAssertGreaterThan(large, small)
    }

    func testBalancedLinesRespectMaxLines() {
        let lines = TitleFitter.balancedLines(for: "one two three four five six seven eight", maxLines: 3)
        XCTAssertLessThanOrEqual(lines.count, 3)
        XCTAssertGreaterThan(lines.count, 0)
    }
}
