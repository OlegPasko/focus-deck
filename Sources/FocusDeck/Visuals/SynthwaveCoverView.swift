import SwiftUI
import FocusDeckKit

/// Full-bleed retrowave cover for one `CoverSpec`.
///
/// Drawing is delegated to `CoverRenderer`; this view only owns the clock.
/// - `animated == false` (or `intensity == 0`) pauses the timeline, so the cover
///   is a single static frame and never redraws.
/// - Redraws are capped at 24 fps (enough for a slow drift, ~25% cheaper than 30) and
///   `intensity` scales motion, glow and bloom.
struct SynthwaveCoverView: View {
    let spec: CoverSpec
    let palette: SynthPalette
    let animated: Bool
    let intensity: Double
    /// Ambient redraws per second. Lower it when nobody is looking closely.
    var frameRate: Double = SynthwaveCoverView.ambientFrameRate

    @State private var cache = CoverSceneCache()

    init(spec: CoverSpec, palette: SynthPalette, animated: Bool, intensity: Double,
         frameRate: Double = SynthwaveCoverView.ambientFrameRate) {
        self.spec = spec
        self.palette = palette
        self.animated = animated
        self.intensity = intensity
        self.frameRate = frameRate
    }

    /// Motion only exists when the user asked for it and left some intensity.
    private var isRunning: Bool { animated && intensity > 0.02 }

    /// Ambient drift is slow, so 24 fps looks the same as 30 fps and costs less.
    static let ambientFrameRate: Double = 24

    var body: some View {
        let scene = cache.scene(for: spec)
        TimelineView(.animation(minimumInterval: 1.0 / max(4, frameRate), paused: !isRunning)) { timeline in
            Canvas(opaque: true) { context, size in
                let time = isRunning ? timeline.date.timeIntervalSinceReferenceDate : scene.staticPhase
                CoverRenderer.draw(context: &context,
                                   size: size,
                                   scene: scene,
                                   palette: palette,
                                   time: time,
                                   intensity: intensity)
            }
        }
        .background(SynthColor(hex: palette.skyTop).color)
        .accessibilityHidden(true)
    }
}

/// Keeps the generated geometry for the current spec, so a 30 fps redraw never
/// rebuilds the star field, ridge or skyline.
private final class CoverSceneCache {
    private var spec: CoverSpec?
    private var scene: CoverScene?

    func scene(for spec: CoverSpec) -> CoverScene {
        if let scene, spec == self.spec { return scene }
        let built = CoverScene(spec: spec)
        self.spec = spec
        self.scene = built
        return built
    }
}
