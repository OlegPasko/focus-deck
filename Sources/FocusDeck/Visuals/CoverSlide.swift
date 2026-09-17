import SwiftUI
import FocusDeckKit

/// Geometry of the cover hand-off, kept out of the view so the slide can be
/// checked without a running window.
///
/// `progress` is already eased: 0 means the old cover is still in place,
/// 1 means the new cover has settled and the old one has left the stage.
struct CoverSlide {
    var progress: Double

    /// How far the outgoing cover travels, relative to the incoming one.
    static let parallax: Double = 0.34

    var value: Double { min(1, max(0, progress)) }

    func incomingOffset(width: CGFloat) -> CGFloat { width * CGFloat(1 - value) }
    func outgoingOffset(width: CGFloat) -> CGFloat { -width * CGFloat(Self.parallax * value) }

    var incomingOpacity: Double { 0.22 + 0.78 * value }
    var outgoingOpacity: Double { 1 - 0.94 * value }

    var incomingScale: CGFloat { 1 + 0.035 * CGFloat(1 - value) }
    var outgoingScale: CGFloat { 1 - 0.02 * CGFloat(value) }

    /// Horizontal travel of the light sweep, and how bright it is right now.
    var sweepOffset: Double { -0.9 + 1.8 * value }
    var sweepOpacity: Double { sin(Double.pi * value) * 0.9 }

    /// Smooth acceleration in and out, used for the slide clock.
    static func ease(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return clamped < 0.5 ? 4 * clamped * clamped * clamped
                             : 1 - pow(-2 * clamped + 2, 3) / 2
    }
}

/// Diagonal highlight that crosses the stage while the covers swap.
struct CoverSweepOverlay: View {
    let slide: CoverSlide
    let width: CGFloat

    var body: some View {
        LinearGradient(stops: [
            .init(color: Color.white.opacity(0.00), location: 0.00),
            .init(color: Color.white.opacity(0.10), location: 0.36),
            .init(color: Color.white.opacity(0.85), location: 0.50),
            .init(color: Color.white.opacity(0.10), location: 0.64),
            .init(color: Color.white.opacity(0.00), location: 1.00)
        ], startPoint: .leading, endPoint: .trailing)
            .frame(width: width * 0.30, height: .infinity)
            .rotationEffect(.degrees(10))
            .offset(x: width * CGFloat(slide.sweepOffset))
            .opacity(slide.sweepOpacity)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}
