import XCTest
import AppKit
@testable import FocusDeck

final class ArtworkTests: XCTestCase {
    func testEveryGalleryWallpaperIsBundledAndDecodes() throws {
        XCTAssertEqual(ArtworkCatalog.wallpapers.count, 6)
        for wallpaper in ArtworkCatalog.wallpapers {
            let url = try XCTUnwrap(ArtworkCatalog.bundle.url(forResource: wallpaper.resource,
                withExtension: "png", subdirectory: "Covers"))
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertGreaterThan(image.size.width, 1000)
            XCTAssertGreaterThan(image.size.height, 700)
        }
        let selected = Set((0..<60).map { ArtworkCatalog.resource(style: "gallery", seed: UInt64($0)) })
        XCTAssertEqual(selected, Set(ArtworkCatalog.wallpapers.map(\.resource)))
    }

    func testEverlabsVectorIsBundled() throws {
        let url = try XCTUnwrap(ArtworkCatalog.bundle.url(forResource: "everlabs-mark",
            withExtension: "pdf", subdirectory: "Branding"))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }
}
