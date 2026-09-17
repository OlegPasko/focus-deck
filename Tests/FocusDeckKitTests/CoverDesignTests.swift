import XCTest
@testable import FocusDeckKit

final class CoverDesignTests: XCTestCase {
    func testSeedIsStable() {
        XCTAssertEqual(CoverCatalog.seed(from: "Write the report"),
                       CoverCatalog.seed(from: "  write the report  "))
    }

    func testSeedDiffersForDifferentText() {
        XCTAssertNotEqual(CoverCatalog.seed(from: "Task A"), CoverCatalog.seed(from: "Task B"))
    }

    func testSpecIsDeterministic() {
        let first = CoverCatalog.spec(for: "Ship the app")
        let second = CoverCatalog.spec(for: "Ship the app")
        XCTAssertEqual(first, second)
    }

    func testSpecStaysInsideRanges() {
        for index in 0..<200 {
            let spec = CoverCatalog.spec(forSeed: UInt64(index) &* 7919)
            XCTAssertTrue((0..<SynthPalette.catalog.count).contains(spec.paletteIndex))
            XCTAssertTrue((0.0...1.0).contains(spec.horizonY))
            XCTAssertTrue((0.0...1.0).contains(spec.sunX))
            XCTAssertFalse(spec.ridge.isEmpty)
            XCTAssertTrue(spec.ridge.allSatisfy { $0 > 0 })
        }
    }

    func testPaletteWrapsAround() {
        XCTAssertEqual(SynthPalette.palette(at: 0).name, SynthPalette.catalog[0].name)
        XCTAssertEqual(SynthPalette.palette(at: -1).name, SynthPalette.catalog[SynthPalette.catalog.count - 1].name)
    }
}
