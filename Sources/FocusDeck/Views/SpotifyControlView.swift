import SwiftUI

/// The artwork is the only permanent chrome. Details appear above it on hover.
struct SpotifyControlView: View {
    static let tileSize: CGFloat = 60
    @ObservedObject var player: SpotifyController
    var isWindowVisible = true
    var showsDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @FocusState private var focused: Bool

    private var expanded: Bool { showsDetails || hovered || focused }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if expanded {
                details.padding(.bottom, 12)
            }
            Button { player.togglePlayback() } label: {
                ZStack {
                    Rectangle().fill(Color(red: 0.08, green: 0.08, blue: 0.13))
                    if let url = player.snapshot.artworkURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { Color.white.opacity(0.04) }
                    }
                    Color.black.opacity(expanded ? 0.35 : 0.20)
                    if player.isBusy {
                        ProgressView().controlSize(.small)
                    } else if !player.snapshot.isPlaying || expanded {
                        Image(systemName: player.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .medium))
                            .shadow(color: .black.opacity(0.7), radius: 6)
                    } else {
                        VStack {
                            Spacer()
                            HStack { Spacer(); playingBars.padding(7) }
                        }
                    }
                }
                .frame(width: Self.tileSize, height: Self.tileSize)
                .clipped()
                .overlay(Rectangle().strokeBorder(.white.opacity(expanded ? 0.35 : 0.14)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focused)
            .disabled(player.isBusy)
            .accessibilityLabel(player.snapshot.isPlaying ? "Pause Spotify" : "Play Spotify")
            .accessibilityValue(player.trackDescription)
            .help(player.message ?? player.trackDescription)
            .opacity(expanded ? 1 : 0.50)
        }
        .foregroundStyle(.white)
        .background(PointerHoverRegion { hovered = $0 })
        // The expanded panel must keep its real bounds for mouse hit testing.
        // Only the artwork button is constrained to tileSize.
        .fixedSize()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expanded)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = player.message {
                Text("Spotify").font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.snapshot.title.isEmpty ? "Spotify" : player.snapshot.title)
                            .font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Text(player.snapshot.artist.isEmpty ? "Choose music in Spotify" : player.snapshot.artist)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { player.nextTrack() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 13)).frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .disabled(player.isBusy)
                    .help("Next track in Spotify")
                    .accessibilityLabel("Next Spotify track")
                }
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(Color(red: 0.035, green: 0.035, blue: 0.065).opacity(0.80))
        .overlay(Rectangle().strokeBorder(.white.opacity(0.12)))
    }

    private var playingBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: reduceMotion || !isWindowVisible)) { context in
            let time = reduceMotion || !isWindowVisible ? 0 : context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.55))
                        .frame(width: 3, height: 5 + 10 * (0.5 + 0.5 * sin(time * 2.2 + Double(index) * 1.8)))
                }
            }
            .frame(height: 16, alignment: .bottom)
            .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .accessibilityHidden(true)
    }
}

/// Track even when another app owns keyboard focus on the user's main screen.
struct PointerHoverRegion: NSViewRepresentable {
    var changed: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView(changed: changed) }
    func updateNSView(_ view: TrackingView, context: Context) { view.changed = changed }

    final class TrackingView: NSView {
        var changed: (Bool) -> Void
        private var area: NSTrackingArea?

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            // inVisibleRect resizes automatically. Replacing the area on every clock
            // tick emits spurious exits and collapses the details under the pointer.
            if area == nil {
                let newArea = NSTrackingArea(rect: .zero,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
                addTrackingArea(newArea)
                area = newArea
            }
        }
        override func mouseEntered(with event: NSEvent) { changed(true) }
        override func mouseExited(with event: NSEvent) { changed(false) }
    }
}
