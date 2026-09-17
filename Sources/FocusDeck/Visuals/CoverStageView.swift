import SwiftUI
import AppKit
import FocusDeckKit

/// The cover stage: one retrowave cover on screen, replaced with a horizontal
/// slide whenever the focused task changes.
///
/// Behaviour:
/// - a new task slides in from the trailing edge while the old cover slides out
///   with a shorter, slower "parallax" travel, plus a cross fade and a light sweep;
/// - the transition runs off absolute dates, so it starts exactly once per
///   `item?.id` change and never restarts on unrelated state updates;
/// - duration and enabled state come from `FocusSettings.slideDuration` /
///   `animationEnabled`; when the slide is off the covers are swapped with a hard cut.
struct CoverStageView: View {
    let item: FocusItem?
    let settings: FocusSettings
    /// The window can tell us it is hidden, so we stop drawing and save power.
    var isWindowVisible: Bool = true
    /// Ambient redraws per second.
    var ambientFrameRate: Double = 24

    /// One cover on stage: identity plus the deterministic spec behind it.
    private struct Entry: Equatable {
        var id: String
        var spec: CoverSpec

        init(item: FocusItem?) {
            self.id = item?.id ?? "empty"
            self.spec = CoverCatalog.spec(forSeed: item?.coverSeed ?? CoverCatalog.seed(from: "focus"))
        }
    }

    /// The cover that must be on screen right now. It is DERIVED from `item` on every
    /// render, never stored: a stored copy can go stale when SwiftUI hands us a new item.
    private var current: Entry { Entry(item: item) }

    /// The cover leaving the stage, kept only while a slide runs.
    @State private var outgoing: Entry?
    /// The last cover we showed, so we know what to slide away from.
    @State private var lastEntry: Entry?
    @State private var slideStart: Date?
    @State private var isSliding = false
    @State private var cleanup: Task<Void, Never>?

    init(item: FocusItem?, settings: FocusSettings, isWindowVisible: Bool = true,
         ambientFrameRate: Double = 24) {
        self.item = item
        self.settings = settings
        self.isWindowVisible = isWindowVisible
        self.ambientFrameRate = ambientFrameRate
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isSliding)) { timeline in
                let slide = CoverSlide(progress: easedProgress(at: timeline.date))
                ZStack {
                    Color.black

                    if let previous = outgoing, previous.id != current.id {
                        stageCover(previous, incoming: false, slide: slide, width: width)
                    }

                    stageCover(current, incoming: true, slide: slide, width: width)

                    if settings.coverStyle == "classic" {
                        CoverSweepOverlay(slide: slide, width: width)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .background(Color.black)
        .onAppear { lastEntry = current }
        .onChange(of: current) { next in startSlide(to: next) }
    }

    // MARK: - Covers

    /// Places one cover on the stage. While the slide runs, the meeting edges are
    /// faded out so the hand-off has no hard seam; at rest the mask is skipped.
    @ViewBuilder
    private func stageCover(_ entry: Entry, incoming: Bool, slide: CoverSlide, width: CGFloat) -> some View {
        let placed = cover(entry)
            .offset(x: incoming ? slide.incomingOffset(width: width) : slide.outgoingOffset(width: width))
            .scaleEffect(incoming ? slide.incomingScale : slide.outgoingScale)
            .opacity(incoming ? slide.incomingOpacity : slide.outgoingOpacity)

        if isSliding {
            placed.mask(
                LinearGradient(stops: incoming
                    ? [.init(color: .clear, location: 0.00),
                       .init(color: .black, location: 0.16),
                       .init(color: .black, location: 1.00)]
                    : [.init(color: .black, location: 0.00),
                       .init(color: .black, location: 0.84),
                       .init(color: .clear, location: 1.00)],
                    startPoint: .leading, endPoint: .trailing)
            )
        } else {
            placed
        }
    }

    @ViewBuilder
    private func cover(_ entry: Entry) -> some View {
        if settings.coverStyle == "plain" {
            Color(red: 0.035, green: 0.04, blue: 0.07)
        } else if settings.coverStyle == "classic" {
            SynthwaveCoverView(spec: entry.spec,
                           palette: SynthPalette.palette(at: settings.paletteOverride ?? entry.spec.paletteIndex),
                           animated: ambientMotion,
                           intensity: reduceMotion ? 0 : settings.animationIntensity,
                           frameRate: ambientFrameRate)
            .id(entry.id)
        } else {
            ArtworkCoverView(name: ArtworkCatalog.resource(style: settings.coverStyle, seed: entry.spec.seed))
                .id(entry.id)
        }
    }

    // MARK: - Clock

    /// The system "Reduce motion" switch wins over the app setting.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Ambient motion stops when the window is hidden, so a background window costs nothing.
    private var ambientMotion: Bool {
        settings.animationEnabled && !reduceMotion && isWindowVisible
    }

    private var slideDuration: Double {
        settings.animationEnabled && !reduceMotion ? max(0, settings.slideDuration) : 0
    }

    private func rawProgress(at date: Date) -> Double {
        guard let start = slideStart, slideDuration > 0.001 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / slideDuration))
    }

    private func easedProgress(at date: Date) -> Double {
        CoverSlide.ease(rawProgress(at: date))
    }

    // MARK: - Transition

    /// Start the slide when a different task arrives. The cover itself is already
    /// correct without this; the slide is only the animation on top of it.
    private func startSlide(to next: Entry) {
        defer { lastEntry = next }
        guard let previous = lastEntry, previous.id != next.id else { return }

        cleanup?.cancel()
        cleanup = nil

        let changesWithTask = settings.coverStyle == "gallery" || settings.coverStyle == "classic"
        guard changesWithTask, slideDuration > 0.05 else {
            outgoing = nil
            slideStart = nil
            isSliding = false
            return
        }

        outgoing = previous
        slideStart = Date()
        isSliding = true

        let duration = slideDuration
        cleanup = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            outgoing = nil
            slideStart = nil
            isSliding = false
        }
    }
}
