import SwiftUI
import AppKit

struct EverlabsLinkView: View {
    let visible: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let destination = URL(string: "https://everlabs.com")!
    private static let logo = ArtworkCatalog.bundle
        .url(forResource: "everlabs-mark", withExtension: "pdf", subdirectory: "Branding")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Link(destination: Self.destination) {
            Group {
                if let logo = Self.logo {
                    Image(nsImage: logo).resizable().scaledToFit()
                }
            }
            .frame(width: 30, height: 34)
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Everlabs · everlabs.com")
        .accessibilityLabel("Visit Everlabs")
        .opacity(hovered ? 0.75 : 0.38)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: hovered)
        // Inherit the deck's shared fade transaction, just like the task controls.
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .onHover { hovered = $0 }
    }
}
