import SwiftUI
import FocusDeckKit

/// Palette resolved for drawing: the kit hands out hex strings, the renderer
/// wants colours plus a few derived shades.
struct CoverPalette {
    let skyTop: SynthColor
    let skyMid: SynthColor
    let skyBottom: SynthColor
    let sunTop: SynthColor
    let sunBottom: SynthColor
    let grid: SynthColor
    let ridge: SynthColor
    let accent: SynthColor
    let textTint: SynthColor

    /// Warm haze that sits on the horizon line.
    let floorHaze: SynthColor
    /// Nearly black floor far from the horizon.
    let floorDeep: SynthColor
    /// Lit top of a mountain ridge.
    let ridgeLit: SynthColor
    /// Hazy mountain ridge far away.
    let ridgeHaze: SynthColor

    init(_ palette: SynthPalette) {
        skyTop = SynthColor(hex: palette.skyTop)
        skyMid = SynthColor(hex: palette.skyMid)
        skyBottom = SynthColor(hex: palette.skyBottom)
        sunTop = SynthColor(hex: palette.sunTop)
        sunBottom = SynthColor(hex: palette.sunBottom)
        grid = SynthColor(hex: palette.grid)
        ridge = SynthColor(hex: palette.ridge)
        accent = SynthColor(hex: palette.accent)
        textTint = SynthColor(hex: palette.textTint)

        floorHaze = ridge.mixed(with: sunBottom, 0.30)
        floorDeep = ridge.mixed(with: SynthColor(r: 0, g: 0, b: 0), 0.62)
        ridgeLit = ridge.mixed(with: accent, 0.28)
        ridgeHaze = ridge.mixed(with: skyMid, 0.55)
    }
}

/// Paints a `CoverScene` into a SwiftUI `GraphicsContext`.
///
/// The renderer is stateless: one frame is a pure function of
/// (size, scene, palette, time, intensity). Layer order, back to front:
/// sky -> nebula -> stars -> sun bloom -> sun -> horizon haze -> ridges ->
/// skyline -> floor -> grid/tunnel -> chroma fringe -> scanlines -> vignette.
enum CoverRenderer {

    static func draw(context: inout GraphicsContext,
                     size: CGSize,
                     scene: CoverScene,
                     palette: SynthPalette,
                     time: Double,
                     intensity: Double) {
        guard size.width > 8, size.height > 8 else { return }
        var painter = Painter(context: context,
                              size: size,
                              scene: scene,
                              palette: CoverPalette(palette),
                              time: time,
                              intensity: max(0, min(1, intensity)))
        painter.paint()
        context = painter.context
    }

    // MARK: - Painter

    private struct Painter {
        var context: GraphicsContext
        let size: CGSize
        let scene: CoverScene
        let pal: CoverPalette
        /// Motion clock: `intensity` scales both speed and amplitude.
        let clock: Double
        let motion: Double

        private var w: CGFloat { size.width }
        private var h: CGFloat { size.height }
        private var unit: CGFloat { min(size.width, size.height) }
        private var horizon: CGFloat { h * scene.horizonY }
        private var floorHeight: CGFloat { max(1, h - horizon) }
        private var sunRadius: CGFloat { unit * scene.sunRadiusUnits }
        private var sunCenter: CGPoint {
            // Keep about half the disc clear of the ridge, and the whole disc
            // inside the frame, so the sun always reads as the subject.
            var y = h * scene.sunCenterY
            if let ridgeY = scene.ridgeHeight(at: scene.sunCenterX) {
                y = min(y, CGFloat(ridgeY) * h)
            }
            y = min(max(y, sunRadius + h * 0.012), h - 1)
            return CGPoint(x: w * scene.sunCenterX, y: y)
        }
        private var vanishing: CGPoint { CGPoint(x: w * scene.vanishingX, y: horizon) }
        private var glow: Double { scene.spec.glow }

        init(context: GraphicsContext, size: CGSize, scene: CoverScene, palette: CoverPalette,
             time: Double, intensity: Double) {
            self.context = context
            self.size = size
            self.scene = scene
            self.pal = palette
            self.motion = intensity
            self.clock = time
        }

        // MARK: Frame

        mutating func paint() {
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            applyCameraDrift()

            let spec = scene.spec
            let horizonHaze = pal.sunBottom.mixed(with: pal.grid, 0.25)

            drawSky()
            drawNebula()
            drawStars()
            drawHorizonHaze(color: horizonHaze)
            drawSunHalo()
            drawSunDisc()
            drawChroma(.sky)
            drawRidges()
            drawSkyline()
            drawFloor()
            if spec.variant == .tunnelDrive {
                drawTunnel()
            } else {
                drawGrid()
            }
            drawChroma(.floor)
            drawVeil(color: horizonHaze)
            drawScanlines()
            drawVignette()
        }

        /// Slow camera drift: a tiny pan plus a breath of zoom.
        private mutating func applyCameraDrift() {
            let drift = scene.spec.drift * motion
            guard drift > 0.001 else { return }
            let x = sin(clock * 0.061) * w * 0.013 * drift
            let y = cos(clock * 0.043) * h * 0.010 * drift
            let zoom = 1 + 0.010 * drift
            context.translateBy(x: w / 2 + x, y: h / 2 + y)
            context.scaleBy(x: zoom, y: zoom)
            context.translateBy(x: -w / 2, y: -h / 2)
        }

        // MARK: Sky

        private mutating func drawSky() {
            // Drawn oversized so camera drift never exposes an edge.
            let bleed = max(w, h) * 0.12
            let rect = CGRect(x: -bleed, y: -bleed, width: w + bleed * 2, height: h + bleed * 2)
            let gradient = Gradient(stops: [
                .init(color: pal.skyTop.color, location: 0.00),
                .init(color: pal.skyMid.color, location: 0.58),
                .init(color: pal.skyBottom.color, location: 1.00)
            ])
            context.fill(Path(rect), with: .linearGradient(gradient,
                                                           startPoint: CGPoint(x: 0, y: -bleed),
                                                           endPoint: CGPoint(x: 0, y: horizon)))
        }

        /// Soft colour clouds so the sky is not a flat ramp.
        private mutating func drawNebula() {
            var rng = SeededRandom(seed: scene.spec.seed ^ 0x51ED_2B17)
            for index in 0..<3 {
                let cx = CGFloat(rng.range(0.12, 0.88)) * w
                let cy = CGFloat(rng.range(0.04, 0.42)) * horizon
                let radius = unit * CGFloat(rng.range(0.30, 0.62))
                let tint: SynthColor = index == 1 ? pal.accent : (index == 2 ? pal.sunBottom : pal.skyMid)
                let strength = 0.055 + 0.05 * rng.unit()
                // Squash a circular gradient instead of clipping an elliptical path,
                // so the glow fades out with no visible edge.
                let squash: CGFloat = 0.68
                context.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    layer.scaleBy(x: 1, y: squash)
                    let center = CGPoint(x: cx, y: cy / squash)
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                      width: radius * 2, height: radius * 2)),
                               with: .radialGradient(Self.soft(tint, strength),
                                                     center: center, startRadius: 0, endRadius: radius))
                }
            }
        }

        // MARK: Stars

        private mutating func drawStars() {
            guard !scene.stars.isEmpty else { return }
            let twinkleAmplitude = 0.34 * motion
            var buckets = [[Path]](repeating: [Path](repeating: Path(), count: 3), count: 4)
            for star in scene.stars {
                let side = max(0.8, CGFloat(star.size) * unit)
                let x = CGFloat(star.x) * w - side / 2
                let y = CGFloat(star.y) * h - side / 2
                let rect = CGRect(x: x, y: y, width: side, height: side)
                buckets[star.phaseGroup][star.brightGroup].addRect(rect)
            }
            context.blendMode = .plusLighter
            for phaseGroup in 0..<4 {
                let speed = 0.55 + Double(phaseGroup) * 0.31
                let wave = sin(clock * speed + Double(phaseGroup) * 1.7)
                let twinkle = 0.5 + 0.5 * wave
                for brightGroup in 0..<3 {
                    let base = [0.30, 0.60, 1.0][brightGroup]
                    let alpha = base * (1 - twinkleAmplitude + twinkleAmplitude * 2 * twinkle) * (0.75 + 0.25 * motion)
                    context.fill(buckets[phaseGroup][brightGroup],
                                 with: .color(pal.textTint.color.opacity(min(1, alpha))))
                }
            }
            context.blendMode = .normal
        }

        // MARK: Sun

        private mutating func drawSunHalo() {
            let radius = sunRadius
            let center = sunCenter
            context.blendMode = .plusLighter
            let rings: [(CGFloat, Double)] = [(3.4, 0.055), (2.3, 0.10), (1.6, 0.14), (1.12, 0.20)]
            for (scale, alpha) in rings {
                let r = radius * scale
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                    width: r * 2, height: r * 2)),
                             with: .radialGradient(Self.soft(pal.sunBottom, alpha * glow),
                                                   center: center, startRadius: 0, endRadius: r))
            }
            // Tight, blurred hot bloom clipped to a small box: cheap but convincing.
            let bloomRadius = radius * 1.55
            let bloomRect = CGRect(x: center.x - bloomRadius, y: center.y - bloomRadius,
                                   width: bloomRadius * 2, height: bloomRadius * 2)
            context.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: bloomRect))
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: radius * 0.22))
                layer.opacity = 0.30 + 0.35 * motion
                layer.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2)),
                           with: .color(pal.sunTop.color))
            }
            context.blendMode = .normal
        }

        private mutating func drawSunDisc() {
            let center = sunCenter
            let radius = sunRadius
            let disc = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            let gradient = Gradient(stops: [
                .init(color: pal.sunTop.color, location: 0.00),
                .init(color: pal.sunTop.mixed(with: pal.sunBottom, 0.55).color, location: 0.34),
                .init(color: pal.sunBottom.color, location: 0.68),
                .init(color: pal.sunBottom.darkened(0.30).color, location: 1.00)
            ])
            // Lit bands: the disc with the slit cuts subtracted (even-odd fill),
            // so the cuts read as dark gaps instead of holes into the sky.
            let bands = Path { path in
                path.addRect(disc)
                for slit in scene.slits {
                    let top = center.y + radius * CGFloat(slit.top)
                    let bottom = center.y + radius * CGFloat(slit.bottom)
                    path.addRect(CGRect(x: disc.minX - 2, y: top,
                                        width: disc.width + 4, height: max(0.6, bottom - top)))
                }
            }
            context.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: disc))
                layer.fill(Path(disc), with: .linearGradient(
                    Gradient(stops: [
                        .init(color: pal.ridge.mixed(with: pal.skyBottom, 0.45).fade(0.95).color, location: 0.04),
                        .init(color: pal.ridge.darkened(0.45).color, location: 0.55),
                        .init(color: pal.ridge.darkened(0.80).color, location: 1.00)
                    ]),
                    startPoint: CGPoint(x: center.x, y: center.y - radius * 0.08),
                    endPoint: CGPoint(x: center.x, y: disc.maxY)))
                layer.fill(bands, with: .linearGradient(gradient,
                                                        startPoint: CGPoint(x: center.x, y: disc.minY),
                                                        endPoint: CGPoint(x: center.x, y: disc.maxY)),
                           style: FillStyle(eoFill: true))
                // Hot core, kept inside the bands.
                layer.drawLayer { inner in
                    inner.clip(to: bands, style: FillStyle(eoFill: true))
                    inner.blendMode = .plusLighter
                    let coreRadius = radius * 0.62
                    let coreCenter = CGPoint(x: center.x, y: center.y - radius * 0.34)
                    inner.fill(Path(ellipseIn: CGRect(x: coreCenter.x - coreRadius,
                                                      y: coreCenter.y - coreRadius,
                                                      width: coreRadius * 2, height: coreRadius * 2)),
                               with: .radialGradient(Self.soft(pal.sunTop.lightened(0.22), 0.22),
                                                     center: coreCenter,
                                                     startRadius: 0, endRadius: coreRadius))
                }
            }
        }

        private mutating func drawHorizonHaze(color: SynthColor) {
            context.blendMode = .plusLighter
            let above = CGRect(x: -w * 0.1, y: horizon - floorHeight * 0.55,
                               width: w * 1.2, height: floorHeight * 0.55)
            context.fill(Path(above), with: .linearGradient(
                Gradient(stops: [
                    .init(color: color.alpha(0).color, location: 0),
                    .init(color: color.fade(0.16 * glow).color, location: 0.72),
                    .init(color: color.fade(0.34 * glow).color, location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: above.minY), endPoint: CGPoint(x: 0, y: horizon)))

            let below = CGRect(x: -w * 0.1, y: horizon, width: w * 1.2, height: floorHeight * 0.35)
            context.fill(Path(below), with: .linearGradient(
                Gradient(stops: [
                    .init(color: color.fade(0.26 * glow).color, location: 0),
                    .init(color: color.alpha(0).color, location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: below.maxY)))

            // Crisp neon horizon line with a wide halo behind it.
            let line = CGMutablePath()
            line.move(to: CGPoint(x: -w * 0.1, y: horizon))
            line.addLine(to: CGPoint(x: w * 1.1, y: horizon))
            let linePath = Path(line)
            context.stroke(linePath, with: .color(color.fade(0.10 * glow).color), lineWidth: max(6, unit * 0.014))
            context.stroke(linePath, with: .color(pal.grid.fade(0.30 * glow).color), lineWidth: max(1.5, unit * 0.0035))
            context.blendMode = .normal
        }

        // MARK: Ridges and skyline

        private mutating func drawRidges() {
            if !scene.farRidge.isEmpty {
                fill(ridge: scene.farRidge,
                     top: pal.ridgeHaze.mixed(with: pal.skyMid, 0.25),
                     bottom: pal.ridgeHaze.darkened(0.45),
                     rim: pal.accent.fade(0.10 * (0.4 + 0.6 * motion)))
            }
            if !scene.ridge.isEmpty {
                fill(ridge: scene.ridge,
                     top: pal.ridgeLit,
                     bottom: pal.ridge.darkened(0.35),
                     rim: pal.accent.fade(0.34 * (0.5 + 0.5 * glow)))
            }
        }

        private mutating func fill(ridge points: [CGPoint], top: SynthColor, bottom: SynthColor, rim: SynthColor) {
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: horizon))
                for point in points { path.addLine(to: CGPoint(x: CGFloat(point.x) * w, y: CGFloat(point.y) * h)) }
                path.addLine(to: CGPoint(x: w, y: horizon))
                path.closeSubpath()
            }
            let gradient = Gradient(stops: [
                .init(color: top.color, location: 0.0),
                .init(color: bottom.color, location: 1.0)
            ])
            context.fill(path, with: .linearGradient(gradient,
                                                     startPoint: CGPoint(x: 0, y: horizon - h * 0.30),
                                                     endPoint: CGPoint(x: 0, y: horizon)))

            let rimPath = Path { path in
                path.move(to: CGPoint(x: 0, y: CGFloat(points[0].y) * h))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(point.x) * w, y: CGFloat(point.y) * h)) }
            }
            context.blendMode = .plusLighter
            context.stroke(rimPath, with: .color(rim.fade(0.14).color), lineWidth: max(9, unit * 0.022))
            context.stroke(rimPath, with: .color(rim.fade(0.55).color), lineWidth: max(4, unit * 0.010))
            context.stroke(rimPath, with: .color(rim.color), lineWidth: max(1.2, unit * 0.0026))
            context.blendMode = .normal
        }

        private mutating func drawSkyline() {
            guard !scene.buildings.isEmpty || !scene.farBuildings.isEmpty else { return }
            if !scene.farBuildings.isEmpty {
                let path = buildingsPath(scene.farBuildings)
                context.fill(path, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: pal.ridgeHaze.mixed(with: pal.skyMid, 0.35).color, location: 0),
                        .init(color: pal.ridge.darkened(0.55).color, location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: horizon - h * 0.18), endPoint: CGPoint(x: 0, y: horizon)))
            }
            guard !scene.buildings.isEmpty else { return }
            let path = buildingsPath(scene.buildings)
            context.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: pal.ridge.mixed(with: pal.accent, 0.12).color, location: 0),
                    .init(color: pal.ridge.darkened(0.62).color, location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: horizon - h * 0.22), endPoint: CGPoint(x: 0, y: horizon)))

            // Lit windows, batched into three brightness buckets.
            context.blendMode = .plusLighter
            var buckets = [Path](repeating: Path(), count: 3)
            for building in scene.buildings {
                for window in building.windows {
                    let index = window.brightness > 0.75 ? 2 : (window.brightness > 0.5 ? 1 : 0)
                    let rect = CGRect(x: CGFloat(window.x) * w, y: CGFloat(window.y) * h,
                                      width: max(1, w * 0.0035), height: max(1, h * 0.006))
                    buckets[index].addRect(rect)
                }
            }
            let alphas = [0.16, 0.30, 0.52]
            for index in 0..<3 {
                let tint = index == 2 ? pal.accent : pal.grid
                context.fill(buckets[index], with: .color(tint.color.opacity(alphas[index])))
            }
            // Neon rooflines.
            let roof = Path { path in
                for building in scene.buildings {
                    let top = horizon - CGFloat(building.height) * h
                    path.move(to: CGPoint(x: CGFloat(building.x) * w, y: top))
                    path.addLine(to: CGPoint(x: CGFloat(building.x + building.width) * w, y: top))
                }
            }
            context.stroke(roof, with: .color(pal.accent.fade(0.55).color), lineWidth: max(1, unit * 0.0025))
            context.blendMode = .normal
        }

        private func buildingsPath(_ buildings: [CoverScene.Building]) -> Path {
            Path { path in
                for building in buildings {
                    path.addRect(CGRect(x: CGFloat(building.x) * w,
                                        y: horizon - CGFloat(building.height) * h,
                                        width: CGFloat(building.width) * w,
                                        height: CGFloat(building.height) * h + 2))
                }
            }
        }

        // MARK: Floor

        private mutating func drawFloor() {
            let rect = CGRect(x: -w * 0.05, y: horizon, width: w * 1.1, height: floorHeight + h * 0.05)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: pal.ridge.mixed(with: pal.skyMid, 0.20).color, location: 0.0),
                    .init(color: pal.floorDeep.color, location: 0.55),
                    .init(color: pal.floorDeep.darkened(0.45).color, location: 1.0)
                ]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

            // Sun light pooling on the floor under the disc.
            let poolRadius = sunRadius * 2.1
            let squash: CGFloat = 0.55
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.scaleBy(x: 1, y: squash)
                let center = CGPoint(x: sunCenter.x, y: horizon / squash)
                layer.fill(Path(ellipseIn: CGRect(x: center.x - poolRadius, y: center.y - poolRadius,
                                                  width: poolRadius * 2, height: poolRadius * 2)),
                           with: .radialGradient(Self.soft(pal.sunBottom, 0.22 * glow),
                                                 center: center, startRadius: 0, endRadius: poolRadius))
            }
        }

        private mutating func drawGrid(intensityScale: Double = 1, radialScale: Double = 1) {
            let rowsPath = Path { path in
                let phase = gridPhase(speed: 0.05 + scene.spec.gridSpeed * 0.42)
                for index in 1...scene.rowCount {
                    let depth = Double(index) - phase
                    guard depth > 0.10 else { continue }
                    let y = horizon + floorHeight * CGFloat(1.0 / depth)
                    guard y < h + 4 else { continue }
                    path.move(to: CGPoint(x: -w * 0.05, y: y))
                    path.addLine(to: CGPoint(x: w * 1.05, y: y))
                }
            }
            let fade = Gradient(stops: [
                .init(color: pal.grid.alpha(0).color, location: 0.00),
                .init(color: pal.grid.fade(0.10 * intensityScale).color, location: 0.10),
                .init(color: pal.grid.fade(0.30 * intensityScale).color, location: 0.42),
                .init(color: pal.grid.fade(0.72 * intensityScale).color, location: 0.78),
                .init(color: pal.grid.fade(0.95 * intensityScale).color, location: 1.00)
            ])
            let across = { (from: CGFloat, to: CGFloat) in
                GraphicsContext.Shading.linearGradient(fade, startPoint: CGPoint(x: 0, y: from),
                                                       endPoint: CGPoint(x: 0, y: to))
            }
            context.blendMode = .plusLighter
            context.stroke(rowsPath, with: across(horizon, h), style: StrokeStyle(lineWidth: max(5, unit * 0.012), lineCap: .butt))
            context.stroke(rowsPath, with: across(horizon, h), style: StrokeStyle(lineWidth: max(1.2, unit * 0.0022), lineCap: .butt))

            // Radiating lines, all of them converging on the vanishing point.
            let lines = Path { path in
                for index in -scene.radialLineCount...scene.radialLineCount {
                    let x = vanishing.x + CGFloat(index) * w * 0.075
                    path.move(to: vanishing)
                    path.addLine(to: CGPoint(x: x, y: h + floorHeight))
                }
            }
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: horizon, width: w, height: floorHeight)))
                guard radialScale > 0.02 else { return }
                layer.blendMode = .plusLighter
                layer.opacity = radialScale
                layer.stroke(lines, with: across(horizon, h), style: StrokeStyle(lineWidth: max(4, unit * 0.010), lineCap: .butt))
                layer.stroke(lines, with: across(horizon, h), style: StrokeStyle(lineWidth: max(1, unit * 0.0018), lineCap: .butt))

                // The line straight under the sun is the hot one.
                let centre = Path { path in
                    path.move(to: vanishing)
                    path.addLine(to: CGPoint(x: vanishing.x, y: h + floorHeight))
                }
                layer.opacity = radialScale
                layer.stroke(centre, with: across(horizon, h), style: StrokeStyle(lineWidth: max(2, unit * 0.0045), lineCap: .butt))
            }

            // Leading edge: a bright bar that reads as motion toward the viewer.
            let phase = gridPhase(speed: 0.05 + scene.spec.gridSpeed * 0.42)
            if let y = nearestRowY(phase: phase) {
                let band = CGRect(x: -w * 0.05, y: y - unit * 0.002, width: w * 1.1, height: unit * 0.004)
                context.fill(Path(band), with: .color(pal.grid.lightened(0.45)
                    .fade(0.35 * intensityScale * (0.4 + 0.6 * motion)).color))
            }
            context.blendMode = .normal
        }

        private func gridPhase(speed: Double) -> Double {
            let value = clock * speed
            return value - value.rounded(.down)
        }

        private func nearestRowY(phase: Double) -> CGFloat? {
            for index in 1...scene.rowCount {
                let depth = Double(index) - phase
                guard depth > 0.10 else { continue }
                let y = horizon + floorHeight * CGFloat(1.0 / depth)
                guard y < h else { continue }
                if y > horizon + floorHeight * 0.45 { return y }
            }
            return nil
        }

        /// Tunnel drive: nested portal frames that run out of the vanishing point
        /// while the faint floor grid slides underneath them.
        private mutating func drawTunnel() {
            let speed = 0.55 + scene.spec.gridSpeed * 1.15
            let phase = gridPhase(speed: speed)
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: horizon, width: w, height: floorHeight)))
                layer.blendMode = .plusLighter
                for index in 0..<scene.tunnelRingCount {
                    let depth = Double(index) + 1.0 - phase
                    guard depth > 0.08 else { continue }
                    let shrink = pow(0.845, depth - 1.0)
                    let halfWidth = w * 0.60 * CGFloat(shrink)
                    let halfHeight = h * 0.63 * CGFloat(shrink)
                    guard halfWidth > 3, halfHeight > 3 else { continue }
                    let rect = CGRect(x: vanishing.x - halfWidth, y: horizon - halfHeight,
                                      width: halfWidth * 2, height: halfHeight * 2)
                    let ring = Path(roundedRect: rect, cornerRadius: min(halfWidth, halfHeight) * 0.34)
                    let near = CGFloat(min(1.0, shrink / 0.5))
                    let alpha = 0.12 + 0.62 * near
                    let width = max(1.0, unit * (0.0012 + 0.0040 * near))
                    let tint = index % 3 == 2 ? pal.accent : pal.grid
                    layer.stroke(ring, with: .color(tint.fade(alpha * 0.15).color), lineWidth: width * 4.5)
                    layer.stroke(ring, with: .color(tint.fade(alpha).color), lineWidth: width)
                }
                // Speed streaks running out of the vanishing point.
                let streaks = Path { path in
                    for index in 0..<16 {
                        let angle = Double(index) / 16.0 * 2 * Double.pi + clock * 0.06
                        path.move(to: CGPoint(x: vanishing.x + CGFloat(cos(angle)) * unit * 0.08,
                                              y: vanishing.y + CGFloat(sin(angle)) * unit * 0.08))
                        path.addLine(to: CGPoint(x: vanishing.x + CGFloat(cos(angle)) * unit * 0.72,
                                                 y: vanishing.y + CGFloat(sin(angle)) * unit * 0.72))
                    }
                }
                layer.stroke(streaks, with: .color(pal.grid.fade(0.09 * (0.3 + 0.7 * motion)).color),
                             lineWidth: max(1, unit * 0.0015))
            }
            drawGrid(intensityScale: 0.32, radialScale: 0.26)
        }

        // MARK: Finishing passes

        /// Red / cyan split on the strongest edges: the CRT look.
        ///
        /// Split in two passes so the ridge and the skyline keep covering the
        /// fringes of the sky pass, instead of fringes floating over them.
        private enum ChromaPass { case sky, floor }

        private mutating func drawChroma(_ pass: ChromaPass) {
            let chroma = scene.spec.chroma
            guard chroma > 0.02 else { return }
            let offset = unit * CGFloat(0.0012 + 0.0030 * chroma)
            let edges = Path { path in
                switch pass {
                case .sky:
                    path.addEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius,
                                               width: sunRadius * 2, height: sunRadius * 2))
                    path.move(to: CGPoint(x: 0, y: horizon))
                    path.addLine(to: CGPoint(x: w, y: horizon))
                case .floor:
                    for index in 1...scene.rowCount where index <= 9 {
                        let depth = Double(index) - gridPhase(speed: 0.05 + scene.spec.gridSpeed * 0.42)
                        guard depth > 0.10 else { continue }
                        let y = horizon + floorHeight * CGFloat(1.0 / depth)
                        guard y < h else { continue }
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                }
            }
            let strength = 0.10 + 0.30 * chroma
            let thickness = max(1, unit * 0.0016)
            let clipRect = pass == .sky
                ? CGRect(x: 0, y: 0, width: w, height: horizon + 1)
                : CGRect(x: 0, y: horizon, width: w, height: floorHeight)
            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))
                layer.blendMode = .plusLighter
                layer.translateBy(x: -offset, y: 0)
                layer.stroke(edges, with: .color(SynthColor(r: 1.0, g: 0.10, b: 0.32).fade(strength).color),
                             lineWidth: thickness)
                layer.translateBy(x: offset * 2, y: 0)
                layer.stroke(edges, with: .color(SynthColor(r: 0.15, g: 0.85, b: 1.0).fade(strength).color),
                             lineWidth: thickness)
            }
        }

        /// Whole-frame bloom veil: lifts the shadows the way a real lens would.
        private mutating func drawVeil(color: SynthColor) {
            guard glow > 0.05 else { return }
            context.blendMode = .plusLighter
            context.opacity = 0.035 * glow * (0.55 + 0.45 * motion)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Self.soft(color, 1),
                                               center: CGPoint(x: sunCenter.x, y: horizon),
                                               startRadius: 0, endRadius: max(w, h) * 0.95))
            context.opacity = 1
            context.blendMode = .normal
        }

        private mutating func drawScanlines() {
            let strength = scene.spec.scanlines
            guard strength > 0.01 else { return }
            let spacing = max(2, unit / 300)
            let drift = motion * spacing * CGFloat((clock * 0.11).truncatingRemainder(dividingBy: 1))
            let fade = Gradient(stops: [
                .init(color: Color.black.opacity(0), location: 0.0),
                .init(color: Color.black.opacity(0.35), location: 0.5),
                .init(color: Color.black.opacity(0), location: 1.0)
            ])
            let path = Path { path in
                var y = -spacing + drift
                while y < h + spacing {
                    path.addRect(CGRect(x: 0, y: y, width: w, height: spacing * 0.52))
                    y += spacing
                }
            }
            context.opacity = strength * 0.42 * (0.55 + 0.45 * motion)
            context.fill(path, with: .linearGradient(fade,
                                                     startPoint: CGPoint(x: 0, y: 0),
                                                     endPoint: CGPoint(x: 0, y: h)))
            context.opacity = 1
        }

        private mutating func drawVignette() {
            let strength = scene.spec.vignette
            guard strength > 0.01 else { return }
            let alpha = 0.26 + 0.44 * strength
            let aspect = h / w
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: h * aspect)))
                layer.scaleBy(x: 1, y: aspect)
                layer.fill(Path(CGRect(origin: .zero, size: size)),
                           with: .radialGradient(
                            Gradient(stops: [
                                .init(color: Color.black.opacity(0), location: 0.0),
                                .init(color: Color.black.opacity(alpha * 0.35), location: 0.62),
                                .init(color: Color.black.opacity(alpha), location: 1.0)
                            ]),
                            center: CGPoint(x: w / 2, y: h * 0.46),
                            startRadius: unit * 0.20,
                            endRadius: max(w, h) * 0.72))
            }
        }

        // MARK: Helpers

        /// Radial gradient that fades a tint out to nothing.
        static func soft(_ color: SynthColor, _ alpha: Double) -> Gradient {
            Gradient(stops: [
                .init(color: color.fade(alpha).color, location: 0.0),
                .init(color: color.fade(alpha * 0.45).color, location: 0.45),
                .init(color: color.fade(alpha * 0.14).color, location: 0.75),
                .init(color: color.alpha(0).color, location: 1.0)
            ])
        }
    }
}
