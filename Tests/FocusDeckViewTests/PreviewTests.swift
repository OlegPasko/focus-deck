import XCTest
import SwiftUI
import AppKit
import FocusDeckKit
@testable import FocusDeck

final class PreviewTests: XCTestCase {
    @MainActor
    func testRenderResponsiveDeck() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deck-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FocusStore(fileURL: directory.appendingPathComponent("focus.json"), writerName: "preview")
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        settings.settings.animationEnabled = false
        settings.settings.coverStyle = "ocean"
        let model = AppModel(store: store, settings: settings, loadCredentials: false)
        let cases: [(String, CGSize, String)] = [
            ("deck-wide", CGSize(width: 1440, height: 900), "Make room for\none good idea."),
            ("deck-portrait", CGSize(width: 740, height: 1000), "Ship Focus Deck to the second screen"),
            ("deck-small", CGSize(width: 420, height: 360), "Перевірити новий дизайн і підключити завдання з Todoist"),
            ("deck-long", CGSize(width: 700, height: 450), String(repeating: "Review the changes and keep the current task in focus. ", count: 4))
        ]
        for (name, size, title) in cases {
            store.setFocus(title: title)
            try render(DeckView(model: model, startsModel: false), name: name, size: size)
        }
        store.mutate { $0.current = nil }
        try render(DeckView(model: model, startsModel: false), name: "deck-empty", size: CGSize(width: 700, height: 450))
    }

    @MainActor
    func testRenderSpotifyStates() throws {
        for playing in [true, false] {
            let player = SpotifyController(snapshot: SpotifySnapshot(isPlaying: playing,
                title: "We Can Fix Everything", artist: "Kevin Koontz", volume: 42), message: nil)
            for expanded in [true, false] {
                let view = ZStack(alignment: .bottomTrailing) {
                    Color(red: 0.06, green: 0.05, blue: 0.09)
                    SpotifyControlView(player: player, isWindowVisible: false, showsDetails: expanded).padding(24)
                }
                try render(view, name: "spotify-\(playing ? "playing" : "paused")-\(expanded ? "details" : "quiet")",
                           size: CGSize(width: 320, height: 240))
            }
        }
    }

    @MainActor
    func testRenderWallpaperGalleryAndEverlabsHover() throws {
        for wallpaper in ArtworkCatalog.wallpapers {
            let view = ZStack(alignment: .bottomLeading) {
                ArtworkCoverView(name: wallpaper.resource)
                EverlabsLinkView(visible: true).padding(24)
            }
            try render(view, name: "wallpaper-\(wallpaper.id)", size: CGSize(width: 960, height: 540))
        }
        try render(EverlabsLinkView(visible: false), name: "everlabs-hidden", size: CGSize(width: 60, height: 60))
    }

    @MainActor
    func testRenderMeetingReminder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for seconds in [600, 60, 0] {
            let event = MeetingEvent(id: "sample", title: "Design review with the team", start: now.addingTimeInterval(Double(seconds)), end: now.addingTimeInterval(3600))
            for size in [CGSize(width: 360, height: 220), CGSize(width: 900, height: 450)] {
                let view = FocusTitleView(item: nil, settings: .deckDefaults, emptyText: "One thing at a time.", meeting: event, now: now)
                    .padding(24).background(Color(red: 0.08, green: 0.08, blue: 0.14))
                try render(view, name: "meeting-\(seconds)-\(Int(size.width))", size: size)
            }
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, name: String, size: CGSize) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "Could not render \(name)")
        XCTAssertEqual(image.width, Int(size.width))
        XCTAssertEqual(image.height, Int(size.height))
        if let output = ProcessInfo.processInfo.environment["FOCUSDECK_PREVIEW_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
}
