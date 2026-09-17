import Foundation

/// Shared by the gallery, settings, and bundled image loader.
enum ArtworkCatalog {
    struct Wallpaper: Identifiable {
        let id: String
        let title: String
        let resource: String
    }

    static let wallpapers = [
        Wallpaper(id: "ocean", title: "Ocean dusk", resource: "ocean-v1"),
        Wallpaper(id: "dunes", title: "Desert dusk", resource: "dunes-v1"),
        Wallpaper(id: "nord-fjord", title: "Nord · quiet fjord", resource: "nord-fjord-v1"),
        Wallpaper(id: "everforest", title: "Everforest · misty valley", resource: "everforest-v1"),
        Wallpaper(id: "gruvbox-mesa", title: "Gruvbox · dusk mesas", resource: "gruvbox-mesa-v1"),
        Wallpaper(id: "tokyo-rain", title: "Tokyo Night · rain", resource: "tokyo-rain-v1")
    ]

    static var bundle: Bundle {
        Bundle.main.url(forResource: "FocusDeck_FocusDeck", withExtension: "bundle")
            .flatMap(Bundle.init(url:)) ?? Bundle.module
    }

    static func resource(style: String, seed: UInt64) -> String {
        if let fixed = wallpapers.first(where: { $0.id == style }) { return fixed.resource }
        return wallpapers[Int(seed % UInt64(wallpapers.count))].resource
    }
}
