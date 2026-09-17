import XCTest
import AppKit
import SwiftUI
@testable import FocusDeck

final class SpotifyTests: XCTestCase {
    func testDecodeMetadataPreservesUnicodeAndSeparators() throws {
        let snapshot = try SpotifySnapshot(descriptor: response(state: "playing", artwork: "https://i.scdn.co/image/test", volume: 140))
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertEqual(snapshot.title, "Track, \"one\"\nДва")
        XCTAssertEqual(snapshot.artist, "Artist · Band")
        XCTAssertEqual(snapshot.artworkURL?.host, "i.scdn.co")
        XCTAssertEqual(snapshot.volume, 100)
    }

    func testPausedAndStoppedDoNotAnimateAndLocalArtworkIsRejected() throws {
        for state in ["paused", "stopped"] {
            let snapshot = try SpotifySnapshot(descriptor: response(state: state, artwork: "file:///private/cover.jpg", volume: -4))
            XCTAssertFalse(snapshot.isPlaying)
            XCTAssertNil(snapshot.artworkURL)
            XCTAssertEqual(snapshot.volume, 0)
        }
    }

    func testMalformedResponseFails() {
        XCTAssertThrowsError(try SpotifySnapshot(descriptor: NSAppleEventDescriptor(string: "not a playback response")))
    }

    func testScriptsCompileAgainstInstalledSpotifyDictionary() throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyBridge.bundleID) != nil else {
            throw XCTSkip("Spotify is not installed")
        }
        for source in [SpotifyBridge.readScript, SpotifyBridge.commandScript(), SpotifyBridge.commandScript(volume: 42), SpotifyBridge.nextTrackScript] {
            let script = try XCTUnwrap(NSAppleScript(source: source))
            var error: NSDictionary?
            XCTAssertTrue(script.compileAndReturnError(&error), "\(String(describing: error))")
        }
    }

    @MainActor
    func testHoverPanelKeepsItsFullInteractionBounds() {
        let player = SpotifyController(snapshot: SpotifySnapshot(title: "Track", artist: "Artist"), message: nil)
        let collapsed = NSHostingView(rootView: SpotifyControlView(player: player))
        XCTAssertEqual(collapsed.fittingSize.width, 60, accuracy: 0.5)
        XCTAssertEqual(collapsed.fittingSize.height, 60, accuracy: 0.5)

        let expanded = NSHostingView(rootView: SpotifyControlView(player: player, showsDetails: true))
        // A panel squeezed into the tile's bounds renders outside its clickable area.
        XCTAssertGreaterThan(expanded.fittingSize.width, 200)
        XCTAssertGreaterThan(expanded.fittingSize.height, 120)
    }

    private func response(state: String, artwork: String, volume: Int32) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, value) in [state, "Track, \"one\"\nДва", "Artist · Band", artwork].enumerated() {
            list.insert(NSAppleEventDescriptor(string: value), at: index + 1)
        }
        list.insert(NSAppleEventDescriptor(int32: volume), at: 5)
        return list
    }
}
