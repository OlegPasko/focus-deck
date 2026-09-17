// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusDeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FocusDeck", targets: ["FocusDeck"]),
        .executable(name: "focusdeck-cli", targets: ["focusdeck-cli"]),
        .library(name: "FocusDeckKit", targets: ["FocusDeckKit"]),
    ],
    targets: [
        .target(name: "FocusDeckKit", path: "Sources/FocusDeckKit"),
        .executableTarget(name: "FocusDeck", dependencies: ["FocusDeckKit"], path: "Sources/FocusDeck",
                          resources: [.copy("Resources/Covers"), .copy("Resources/Branding")]),
        .executableTarget(name: "focusdeck-cli", dependencies: ["FocusDeckKit"], path: "Sources/focusdeck-cli"),

        .testTarget(name: "FocusDeckViewTests", dependencies: ["FocusDeck"], path: "Tests/FocusDeckViewTests"),
        .testTarget(name: "FocusDeckKitTests", dependencies: ["FocusDeckKit"],
                    path: "Tests/FocusDeckKitTests", resources: [.copy("Fixtures")]),
    ]
)
