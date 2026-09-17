import SwiftUI
import AppKit
import FocusDeckKit

/// Small bridge so menus, buttons and keyboard shortcuts can drive the real NSWindow.
@MainActor
final class DeckWindow: ObservableObject {
    static let shared = DeckWindow()

    weak var window: NSWindow?
    @Published var screenName: String = ""
    /// False while the window is hidden, minimised or on another Space: we stop drawing then.
    @Published var isVisible: Bool = true
    /// True when the deck is the front window. A deck on a second screen is usually not,
    /// so we draw a calmer drift then and save power.
    @Published var isKey: Bool = false

    func attach(_ window: NSWindow) {
        self.window = window
        window.title = "Focus Deck"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert([.resizable, .miniaturizable, .closable])
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
        window.minSize = NSSize(width: 420, height: 360)
        // Remember where the window was, so it returns to the second screen next time.
        window.setFrameAutosaveName("FocusDeckMainWindow")
        if !isOnAnyScreen(window.frame) {
            window.setContentSize(NSSize(width: 1200, height: 680))
            window.center()
        }
        window.backgroundColor = .black
        window.hasShadow = true
        window.isOpaque = true
        applyAlwaysOnTop(AppModel.shared.settings.settings.alwaysOnTop)
        updateScreenName()
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
                                               object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreenName() }
        }
        for name in [NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification,
                     NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification,
                     NSApplication.didHideNotification,
                     NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshVisibility() }
            }
        }
        refreshVisibility()
    }

    /// Visible means: not hidden, not minimised, and actually on a screen we can see.
    func refreshVisibility() {
        guard let window else { isVisible = false; return }
        isVisible = window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
            && !NSApp.isHidden
        isKey = window.isKeyWindow
    }

    func updateScreenName() {
        screenName = window?.screen?.localizedName ?? "main display"
    }

    func applyAlwaysOnTop(_ enabled: Bool) {
        window?.level = enabled ? .floating : .normal
        window?.collectionBehavior = enabled
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .managed, .stationary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .managed]
    }

    /// Send the window to the next display and fill most of it.
    func moveToNextDisplay(fill: Bool = true) {
        guard let window else { return }
        let screens = NSScreen.screens
        guard screens.count > 0 else { return }
        let current = window.screen ?? screens.first!
        let index = screens.firstIndex(of: current) ?? 0
        let next = screens[(index + 1) % screens.count]
        let visible = next.visibleFrame

        if fill {
            let inset: CGFloat = 24
            let target = NSRect(x: visible.minX + inset, y: visible.minY + inset,
                                width: visible.width - inset * 2, height: visible.height - inset * 2)
            window.setFrame(target, display: true, animate: true)
        } else {
            var frame = window.frame
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
            window.setFrame(frame, display: true, animate: true)
        }
        window.makeKeyAndOrderFront(nil)
        updateScreenName()
    }

    /// Fill the current display without entering macOS full screen.
    func fillCurrentDisplay() {
        guard let window, let screen = window.screen ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let inset: CGFloat = 12
        window.setFrame(NSRect(x: visible.minX + inset, y: visible.minY + inset,
                               width: visible.width - inset * 2, height: visible.height - inset * 2),
                        display: true, animate: true)
        updateScreenName()
    }

    /// True when the frame touches a visible part of some display.
    private func isOnAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func center() {
        window?.center()
    }
}

/// Hidden view that hands the hosting NSWindow to `DeckWindow`.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                Task { @MainActor in DeckWindow.shared.attach(window) }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
