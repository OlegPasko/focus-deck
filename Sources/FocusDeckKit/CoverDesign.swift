import Foundation

/// Layout flavour of a generated cover.
public enum CoverVariant: String, Codable, Sendable, CaseIterable {
    case classicSunset   // sun + grid horizon
    case mountainRange   // ridge silhouette + big sun
    case cityGrid        // neon skyline + floor grid
    case tunnelDrive     // perspective tunnel with vanishing point
}

/// Deterministic description of one generated cover. Same seed -> same cover.
public struct CoverSpec: Equatable, Sendable {
    public var seed: UInt64
    public var paletteIndex: Int
    public var variant: CoverVariant
    public var sunX: Double          // 0...1 in normalized cover space
    public var sunY: Double
    public var sunScale: Double      // 0.5...1.5
    public var horizonY: Double      // 0...1
    public var gridSpeed: Double     // 0...1
    public var starDensity: Double   // 0...1
    public var ridge: [Double]       // normalized ridge heights
    public var glow: Double          // 0...1
    public var scanlines: Double     // 0...1
    public var vignette: Double      // 0...1
    public var chroma: Double        // 0...1 chromatic fringe amount
    public var drift: Double         // slow camera drift amount
}

/// Stable string hash (FNV-1a 64). Used so a task always gets the same cover.
public enum StableHash {
    public static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Small deterministic random number generator (SplitMix64).
public struct SeededRandom {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func range(_ low: Double, _ high: Double) -> Double { low + unit() * (high - low) }
    public mutating func int(_ upperBound: Int) -> Int { upperBound <= 0 ? 0 : Int(next() % UInt64(upperBound)) }
}

public enum CoverCatalog {
    /// Number of palettes in `SynthPalette.catalog`.
    public static var paletteCount: Int { SynthPalette.catalog.count }

    public static func seed(from text: String) -> UInt64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return StableHash.fnv1a(trimmed.isEmpty ? "focus" : trimmed.lowercased())
    }

    public static func spec(forSeed seed: UInt64) -> CoverSpec {
        var rng = SeededRandom(seed: seed)
        let paletteIndex = rng.int(max(1, paletteCount))
        let variant = CoverVariant.allCases[rng.int(CoverVariant.allCases.count)]
        let sunScale = rng.range(0.72, 1.35)
        let sunX = rng.range(0.28, 0.72)
        let sunY = rng.range(0.30, 0.46)
        let horizon = rng.range(0.54, 0.68)

        var ridge: [Double] = []
        let ridgeCount = 9 + rng.int(5)
        let ridgeBase = rng.range(0.06, 0.22)
        for index in 0..<ridgeCount {
            let wave = sin(Double(index) * rng.range(0.5, 1.1) + rng.unit() * 6.28)
            ridge.append(max(0.02, ridgeBase + wave * rng.range(0.03, 0.10)))
        }

        return CoverSpec(
            seed: seed,
            paletteIndex: paletteIndex,
            variant: variant,
            sunX: sunX,
            sunY: sunY,
            sunScale: sunScale,
            horizonY: horizon,
            gridSpeed: rng.range(0.35, 1.0),
            starDensity: rng.range(0.35, 0.9),
            ridge: ridge,
            glow: rng.range(0.55, 0.95),
            scanlines: rng.range(0.10, 0.32),
            vignette: rng.range(0.35, 0.7),
            chroma: rng.range(0.15, 0.6),
            drift: rng.range(0.2, 0.8)
        )
    }

    public static func spec(for text: String) -> CoverSpec { spec(forSeed: seed(from: text)) }
}

/// Retrowave colour sets. Colours are hex strings ("RRGGBB") so the kit stays UI-free.
public struct SynthPalette: Equatable, Sendable {
    public let name: String
    public let skyTop: String
    public let skyMid: String
    public let skyBottom: String
    public let sunTop: String
    public let sunBottom: String
    public let grid: String
    public let ridge: String
    public let accent: String
    public let textTint: String

    public static let catalog: [SynthPalette] = [
        SynthPalette(name: "Miami Dusk",  skyTop: "140A2E", skyMid: "5B1170", skyBottom: "FF3D7F",
                     sunTop: "FFE66D", sunBottom: "FF2E63", grid: "00E5FF", ridge: "1B0B33",
                     accent: "FF2E97", textTint: "FFFFFF"),
        SynthPalette(name: "Neon Tokyo",  skyTop: "0B0F2E", skyMid: "231B6B", skyBottom: "7B2FF7",
                     sunTop: "FFD166", sunBottom: "F72585", grid: "4CC9F0", ridge: "100826",
                     accent: "B5179E", textTint: "F8F9FF"),
        SynthPalette(name: "Chrome Vibes",skyTop: "1A0B2E", skyMid: "4A148C", skyBottom: "E040FB",
                     sunTop: "FFF1A8", sunBottom: "FF4E9B", grid: "18FFFF", ridge: "160A2B",
                     accent: "FF8AE2", textTint: "FFFFFF"),
        SynthPalette(name: "Sunset Drive",skyTop: "2B0B3F", skyMid: "8E2DE2", skyBottom: "FF7A18",
                     sunTop: "FFE066", sunBottom: "FF4D00", grid: "00F5D4", ridge: "200B33",
                     accent: "FF9F1C", textTint: "FFFDF7"),
        SynthPalette(name: "Deep Static", skyTop: "05060F", skyMid: "161B4B", skyBottom: "3A0CA3",
                     sunTop: "B8F2FF", sunBottom: "4361EE", grid: "7BF1A8", ridge: "080A1A",
                     accent: "4CC9F0", textTint: "F2F6FF"),
        SynthPalette(name: "Crimson Grid",skyTop: "1B0510", skyMid: "6A0F2E", skyBottom: "FF2D55",
                     sunTop: "FFE8A3", sunBottom: "D00000", grid: "FFAFCC", ridge: "12030A",
                     accent: "FF7B00", textTint: "FFFFFF"),
    ]

    public static func palette(at index: Int) -> SynthPalette {
        guard !catalog.isEmpty else {
            return SynthPalette(name: "Fallback", skyTop: "140A2E", skyMid: "5B1170", skyBottom: "FF3D7F",
                                sunTop: "FFE66D", sunBottom: "FF2E63", grid: "00E5FF", ridge: "1B0B33",
                                accent: "FF2E97", textTint: "FFFFFF")
        }
        let safe = ((index % catalog.count) + catalog.count) % catalog.count
        return catalog[safe]
    }
}
