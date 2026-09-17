import SwiftUI
import AppKit

/// Bundled artwork stays still between task changes. No per-frame wallpaper rendering.
struct ArtworkCoverView: View {
    let name: String

    private static let images: [String: NSImage] = {
        let bundle = ArtworkCatalog.bundle
        return Dictionary(uniqueKeysWithValues: ArtworkCatalog.wallpapers.compactMap { wallpaper in
            let name = wallpaper.resource
            guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Covers"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return (name, image)
        })
    }()

    var body: some View {
        GeometryReader { geometry in
            if let image = Self.images[name] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                Color(red: 0.04, green: 0.04, blue: 0.10)
            }
        }
        .accessibilityHidden(true)
    }
}
