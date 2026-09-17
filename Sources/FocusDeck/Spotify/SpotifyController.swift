import AppKit
import ApplicationServices
import Combine

struct SpotifySnapshot: Equatable {
    var isPlaying = false
    var title = ""
    var artist = ""
    var artworkURL: URL?
    var volume = 50

    init(isPlaying: Bool = false, title: String = "", artist: String = "", artworkURL: URL? = nil, volume: Int = 50) {
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.volume = min(100, max(0, volume))
    }

    init(descriptor: NSAppleEventDescriptor) throws {
        guard descriptor.numberOfItems == 5,
              let state = descriptor.atIndex(1)?.stringValue,
              let title = descriptor.atIndex(2)?.stringValue,
              let artist = descriptor.atIndex(3)?.stringValue,
              let artwork = descriptor.atIndex(4)?.stringValue,
              let volume = descriptor.atIndex(5) else { throw SpotifyFailure.invalidResponse }
        self.init(isPlaying: state == "playing", title: title, artist: artist,
                  artworkURL: URL(string: artwork).flatMap { $0.scheme == "https" ? $0 : nil },
                  volume: Int(volume.int32Value))
    }
}

enum SpotifyFailure: LocalizedError {
    case notRunning, permission, invalidResponse, script(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Open Spotify and choose music, then use this square to play or pause."
        case .permission: return "Click to allow Spotify control. If access was denied, enable Focus Deck → Spotify in System Settings → Privacy & Security → Automation."
        case .invalidResponse: return "Spotify did not return its playback details. Click to try again."
        case .script(let message): return message
        }
    }
}

/// All Apple events address Spotify by bundle ID. No global media keys or system volume.
/// One serial queue keeps scripting off the UI thread and prevents overlapping commands.
final class SpotifyBridge: @unchecked Sendable {
    static let bundleID = "com.spotify.client"
    private let queue = DispatchQueue(label: "com.focusdeck.spotify", qos: .utility)

    static let readScript = """
    with timeout of 3 seconds
        tell application id "com.spotify.client"
            set playbackState to player state as text
            set outputVolume to sound volume
            set trackName to ""
            set trackArtist to ""
            set coverURL to ""
            try
                set trackName to name of current track
                set trackArtist to artist of current track
                set coverURL to artwork url of current track
            end try
            return {playbackState, trackName, trackArtist, coverURL, outputVolume}
        end tell
    end timeout
    """

    static func commandScript(volume: Int? = nil) -> String {
        let command = volume.map { "set sound volume to \(min(100, max(0, $0)))" } ?? "playpause"
        return targetedScript(command)
    }

    static let nextTrackScript = targetedScript("next track")

    private static func targetedScript(_ command: String) -> String {
        return """
        with timeout of 3 seconds
            tell application id "com.spotify.client"
                \(command)
            end tell
        end timeout
        """
    }

    func read(requestPermission: Bool = false, command: String? = nil) async throws -> SpotifySnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    // Checking the process first avoids launching Spotify just to poll it.
                    guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else {
                        throw SpotifyFailure.notRunning
                    }
                    // Request consent before starting a timed command, so the first-click
                    // permission dialog cannot consume the command's timeout.
                    let target = NSAppleEventDescriptor(bundleIdentifier: Self.bundleID)
                    let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, requestPermission)
                    guard status == noErr else { throw SpotifyFailure.permission }
                    if let command { _ = try Self.execute(command) }
                    continuation.resume(returning: try SpotifySnapshot(descriptor: Self.execute(Self.readScript)))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw SpotifyFailure.invalidResponse }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -1743 { throw SpotifyFailure.permission }
            throw SpotifyFailure.script(error[NSAppleScript.errorMessage] as? String ?? "Could not reach Spotify. Click to retry.")
        }
        return result
    }
}

@MainActor
final class SpotifyController: ObservableObject {
    @Published private(set) var snapshot: SpotifySnapshot
    @Published private(set) var message: String?
    @Published private(set) var isBusy = false
    private let bridge = SpotifyBridge()
    private var pollTask: Task<Void, Never>?
    private var reading = false
    private var generation = 0

    init(snapshot: SpotifySnapshot = SpotifySnapshot(), message: String? = "Click to connect to Spotify.") {
        self.snapshot = snapshot
        self.message = message
    }

    var trackDescription: String {
        [snapshot.title, snapshot.artist].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if DeckWindow.shared.isVisible { await self?.refresh() }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }

    func refresh() async {
        guard !reading, !isBusy else { return }
        reading = true
        let version = generation
        defer { reading = false }
        do {
            let result = try await bridge.read()
            guard version == generation else { return }
            snapshot = result
            message = nil
        } catch {
            guard version == generation else { return }
            show(error)
        }
    }

    func togglePlayback() { perform(SpotifyBridge.commandScript()) }
    func nextTrack() { perform(SpotifyBridge.nextTrackScript) }
    func setVolume(_ volume: Int) { perform(SpotifyBridge.commandScript(volume: volume)) }

    private func perform(_ command: String) {
        guard !isBusy else { return }
        isBusy = true
        generation += 1
        Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false }
            do {
                snapshot = try await bridge.read(requestPermission: true, command: command)
                message = nil
                // Spotify can acknowledge the command before publishing its new state.
                try? await Task.sleep(nanoseconds: 250_000_000)
                snapshot = try await bridge.read()
            } catch { show(error) }
        }
    }

    private func show(_ error: Error) {
        snapshot = SpotifySnapshot()
        message = error.localizedDescription
    }
}
