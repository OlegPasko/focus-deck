import SwiftUI
import AppKit
import FocusDeckKit

@main
struct FocusDeckApp: App {
    @NSApplicationDelegateAdaptor(DeckAppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Focus Deck") {
            DeckView(model: model)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 680)
        .commands { DeckCommands(model: model) }
    }
}

final class DeckAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Do not steal focus: at login the deck must appear quietly on the second screen and
        // leave the keyboard where it was. The `open` command still brings it forward.
        NSApp.activate(ignoringOtherApps: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
