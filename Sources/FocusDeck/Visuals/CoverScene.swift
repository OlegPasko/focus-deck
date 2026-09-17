import Foundation
import CoreGraphics
import FocusDeckKit

/// Deterministic, resolution independent geometry for one cover.
///
/// Everything is expressed in normalized cover space (0...1 across, 0...1 down)
/// so the same scene renders cleanly at 700x450 or 2560x1440. This type holds no
/// colours and draws nothing: it is the shared skeleton that `CoverRenderer`
/// paints. Build it once per `CoverSpec` and reuse it for every animation frame.
struct CoverScene {

    /// One star of the sky field. `size` is a fraction of `min(width, height)`.
    struct Star {
        var x: Double
        var y: Double
        var size: Double
        var brightness: Double
        var phaseGroup: Int   // 0...3, drives the twinkle phase
        var brightGroup: Int  // 0...2, buckets the base brightness so stars batch
    }

    /// One lit window of a skyline building, in normalized cover space.
    struct Window {
        var x: Double
        var y: Double
        var brightness: Double
    }

    struct Building {
        var x: Double
        var width: Double
        var height: Double
        var windows: [Window]
    }

    /// A sun slit, in disc radius units: 0 = sun centre, 1 = bottom edge of the disc.
    struct Slit {
        var top: Double
        var bottom: Double
    }

    let spec: CoverSpec
    let horizonY: Double
    let sunCenterX: Double
    let sunCenterY: Double
    /// Sun radius as a fraction of `min(width, height)`.
    let sunRadiusUnits: Double
    let slits: [Slit]
    let stars: [Star]
    /// Near mountain ridge silhouette (left to right, y is the silhouette height).
    let ridge: [CGPoint]
    /// Haze ridge behind it, for depth.
    let farRidge: [CGPoint]
    let buildings: [Building]
    let farBuildings: [Building]
    /// X of the perspective vanishing point (the floor grid converges there).
    let vanishingX: Double
    /// How high the ridge climbs, per variant.
    let ridgeHeightScale: Double
    let rowCount: Int
    let radialLineCount: Int
    let tunnelRingCount: Int
    /// Frozen time used when the cover must render a still frame.
    let staticPhase: Double

    /// Height of the ridge relative to the raw `spec.ridge` values.
    static func ridgeScale(for variant: CoverVariant) -> Double {
        switch variant {
        case .mountainRange: return 1.30
        case .classicSunset: return 0.85
        case .cityGrid:      return 0.25
        case .tunnelDrive:   return 0.50
        }
    }

    init(spec: CoverSpec) {
        self.spec = spec

        var rng = SeededRandom(seed: spec.seed ^ 0xA5A5_5A5A_1234_9E37)

        let horizon = min(0.82, max(0.42, spec.horizonY))
        self.horizonY = horizon
        self.sunCenterX = min(0.9, max(0.1, spec.sunX))
        self.sunCenterY = min(0.72, max(0.18, spec.sunY))
        self.sunRadiusUnits = 0.29 * min(1.45, max(0.5, spec.sunScale))
        let ridgeHeightScale = Self.ridgeScale(for: spec.variant)
        self.ridgeHeightScale = ridgeHeightScale
        self.rowCount = 26
        self.radialLineCount = 14
        self.tunnelRingCount = 17
        self.staticPhase = Double(spec.seed % 4096) / 4096.0 * 24.0

        // Star field: denser at the top of the sky, a few brighter anchors.
        let starCount = Int((40 + spec.starDensity * 250).rounded())
        var stars: [Star] = []
        stars.reserveCapacity(starCount)
        for _ in 0..<starCount {
            let x = rng.unit()
            let y = pow(rng.unit(), 1.75) * horizon * 0.96
            let brightness = pow(rng.range(0.28, 1.0), 1.25)
            stars.append(Star(x: x, y: y,
                              size: rng.range(0.0011, 0.0034) * (brightness > 0.8 ? 1.6 : 1.0),
                              brightness: brightness,
                              phaseGroup: rng.int(4),
                              brightGroup: min(2, Int(brightness * 3))))
        }
        self.stars = stars

        // Sun slits: thin near the sun's waist, growing toward the bottom edge.
        let slitCount = 7 + rng.int(7)
        var slits: [Slit] = []
        var cursor = rng.range(0.0, 0.12)
        for index in 0..<slitCount {
            let growth = Double(index) / Double(max(1, slitCount - 1))
            let thickness = 0.014 + 0.022 * growth
            slits.append(Slit(top: cursor, bottom: cursor + thickness))
            cursor += thickness + (0.038 + 0.082 * growth) * rng.range(0.88, 1.18)
            if cursor > 1.02 { break }
        }
        self.slits = slits

        // Mountain ridges.
        let scaledRidge = spec.ridge.map { max(0.0, $0) * ridgeHeightScale }
        self.ridge = Self.silhouette(values: scaledRidge, horizon: horizon, offset: 0)
        let far = scaledRidge.enumerated().map { index, value -> Double in
            let blend = sin(Double(index) * 1.7 + 0.9) * 0.35
            return max(0.0, (value * 0.66 + blend * 0.05))
        }
        self.farRidge = Self.silhouette(values: far, horizon: horizon, offset: 0.012)

        // Neon skyline (only used by the cityGrid variant).
        var nearBuildings: [Building] = []
        var farBuildings: [Building] = []
        if spec.variant == .cityGrid {
            var x = -0.05
            while x < 1.05 {
                let width = rng.range(0.028, 0.086)
                let profile = 0.55 + 0.75 * sin(Double.pi * min(1.0, max(0.0, x + width / 2)))
                let height = rng.range(0.055, 0.185) * profile
                nearBuildings.append(Self.makeBuilding(x: x, width: width, height: height,
                                                       horizon: horizon, rng: &rng, litFraction: 0.42))
                if rng.unit() < 0.85 {
                    farBuildings.append(Self.makeBuilding(x: x + rng.range(-0.02, 0.03),
                                                          width: width * rng.range(0.9, 1.4),
                                                          height: height * rng.range(0.35, 0.62) + 0.02,
                                                          horizon: horizon, rng: &rng, litFraction: 0.22))
                }
                x += width + rng.range(0.002, 0.014)
            }
        }
        self.buildings = nearBuildings
        self.farBuildings = farBuildings

        // The grid always converges under the sun, pulled a little toward centre
        // so the composition stays balanced.
        self.vanishingX = min(0.92, max(0.08, 0.5 + (self.sunCenterX - 0.5) * 0.8))
    }

    /// Height of the near ridge silhouette at a normalized x, or nil when there
    /// is no ridge to speak of. The renderer uses it to keep the sun a hero shot
    /// instead of hiding it behind a tall mountain.
    func ridgeHeight(at x: Double) -> Double? {
        guard ridge.count >= 2 else { return nil }
        let position = min(1, max(0, x)) * Double(ridge.count - 1)
        let index = min(Int(position), ridge.count - 2)
        let fraction = position - Double(index)
        let a = Double(ridge[index].y)
        let b = Double(ridge[index + 1].y)
        let y = a + (b - a) * fraction
        // Only worth using when the silhouette actually climbs above the horizon.
        return y < horizonY - 0.02 ? y : nil
    }

    // MARK: - Builders

    /// Sample a smooth silhouette across the full width using Catmull-Rom.
    private static func silhouette(values: [Double], horizon: Double, offset: Double) -> [CGPoint] {
        guard values.count >= 2 else {
            return [CGPoint(x: 0, y: horizon), CGPoint(x: 1, y: horizon)]
        }
        let samples = 128
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        let last = values.count - 1
        for s in 0..<samples {
            let t = Double(s) / Double(samples - 1) * Double(last)
            let i = min(Int(t), last - 1)
            let f = t - Double(i)
            let p0 = values[max(0, i - 1)]
            let p1 = values[i]
            let p2 = values[i + 1]
            let p3 = values[min(last, i + 2)]
            let v = catmullRom(p0, p1, p2, p3, f)
            let height = min(0.75, max(0.0, v + offset))
            points.append(CGPoint(x: Double(s) / Double(samples - 1), y: horizon - height))
        }
        return points
    }

    private static func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t
                      + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                      + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    private static func makeBuilding(x: Double,
                                     width: Double,
                                     height: Double,
                                     horizon: Double,
                                     rng: inout SeededRandom,
                                     litFraction: Double) -> Building {
        let columns = max(2, Int(width / 0.011))
        let rows = max(2, Int(height / 0.021))
        var windows: [Window] = []
        if columns * rows <= 220 {
            let cellW = width / Double(columns)
            let cellH = height / Double(rows)
            for column in 0..<columns {
                for row in 0..<rows {
                    guard rng.unit() < litFraction else { continue }
                    windows.append(Window(x: x + cellW * (Double(column) + 0.32),
                                          y: horizon - height + cellH * (Double(row) + 0.28),
                                          brightness: rng.range(0.35, 1.0)))
                }
            }
        }
        return Building(x: x, width: width, height: height, windows: windows)
    }
}
