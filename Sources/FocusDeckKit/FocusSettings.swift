import Foundation
import Combine

/// User settings for the deck. Stored as JSON so the CLI can read and change them too.
public struct FocusSettings: Codable, Equatable, Sendable {
    public var textScale: Double          // 0.4 ... 2.5, multiplies the auto-fitted font size
    public var uppercase: Bool
    public var alwaysOnTop: Bool
    public var showQueue: Bool
    public var showClock: Bool
    public var showElapsed: Bool
    public var showCoverTitle: Bool
    public var animationEnabled: Bool
    public var animationIntensity: Double // 0 ... 1
    public var slideDuration: Double      // seconds for the cover slide transition
    public var backdropDarkness: Double   // 0 ... 0.8 overlay on the cover
    public var titleScrimStrength: Double // 0 ... 0.7 feathered scrim behind the title block
    public var paletteOverride: Int?      // nil = colour comes from the task seed
    public var coverStyle: String         // gallery, a wallpaper ID, classic, plain
    public var startAtLogin: Bool
    public var calendarEnabled: Bool
    public var calendarLeadMinutes: Int
    public var selectedCalendarIDs: [String]? // nil = all calendars; [] = none
    public var todoistEnabled: Bool
    public var todoistFilter: String      // example: "today" or "##Work"
    public var todoistRefreshMinutes: Double
    public var todoistTokenPresent: Bool  // read-only flag kept in sync by the app

    public init(textScale: Double = 1.0,
                uppercase: Bool = false,
                alwaysOnTop: Bool = true,
                showQueue: Bool = false,
                showClock: Bool = false,
                showElapsed: Bool = true,
                showCoverTitle: Bool = false,
                animationEnabled: Bool = true,
                animationIntensity: Double = 0.7,
                slideDuration: Double = 0.4,
                backdropDarkness: Double = 0.24,
                titleScrimStrength: Double = 0.34,
                paletteOverride: Int? = nil,
                coverStyle: String = "gallery",
                startAtLogin: Bool = false,
                calendarEnabled: Bool = false,
                calendarLeadMinutes: Int = 10,
                selectedCalendarIDs: [String]? = nil,
                todoistEnabled: Bool = false,
                todoistFilter: String = "today | overdue",
                todoistRefreshMinutes: Double = 5,
                todoistTokenPresent: Bool = false) {
        self.textScale = textScale
        self.uppercase = uppercase
        self.alwaysOnTop = alwaysOnTop
        self.showQueue = showQueue
        self.showClock = showClock
        self.showElapsed = showElapsed
        self.showCoverTitle = showCoverTitle
        self.animationEnabled = animationEnabled
        self.animationIntensity = animationIntensity
        self.slideDuration = slideDuration
        self.backdropDarkness = backdropDarkness
        self.titleScrimStrength = titleScrimStrength
        self.paletteOverride = paletteOverride
        self.coverStyle = coverStyle
        self.startAtLogin = startAtLogin
        self.calendarEnabled = calendarEnabled
        self.calendarLeadMinutes = min(120, max(1, calendarLeadMinutes))
        self.selectedCalendarIDs = selectedCalendarIDs
        self.todoistEnabled = todoistEnabled
        self.todoistFilter = todoistFilter
        self.todoistRefreshMinutes = todoistRefreshMinutes
        self.todoistTokenPresent = todoistTokenPresent
    }

    public static let deckDefaults = FocusSettings()

    /// Tolerant decoding: a settings file written by an older build must not throw,
    /// and any field we do not know about is ignored.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FocusSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil ?? fallback
        }
        self.init(
            textScale: value(.textScale, defaults.textScale),
            uppercase: value(.uppercase, defaults.uppercase),
            alwaysOnTop: value(.alwaysOnTop, defaults.alwaysOnTop),
            showQueue: value(.showQueue, defaults.showQueue),
            showClock: value(.showClock, defaults.showClock),
            showElapsed: value(.showElapsed, defaults.showElapsed),
            showCoverTitle: value(.showCoverTitle, defaults.showCoverTitle),
            animationEnabled: value(.animationEnabled, defaults.animationEnabled),
            animationIntensity: value(.animationIntensity, defaults.animationIntensity),
            slideDuration: value(.slideDuration, defaults.slideDuration),
            backdropDarkness: value(.backdropDarkness, defaults.backdropDarkness),
            titleScrimStrength: value(.titleScrimStrength, defaults.titleScrimStrength),
            paletteOverride: value(.paletteOverride, defaults.paletteOverride),
            coverStyle: value(.coverStyle, defaults.coverStyle),
            startAtLogin: value(.startAtLogin, defaults.startAtLogin),
            calendarEnabled: value(.calendarEnabled, defaults.calendarEnabled),
            calendarLeadMinutes: value(.calendarLeadMinutes, defaults.calendarLeadMinutes),
            selectedCalendarIDs: value(.selectedCalendarIDs, defaults.selectedCalendarIDs),
            todoistEnabled: value(.todoistEnabled, defaults.todoistEnabled),
            todoistFilter: value(.todoistFilter, defaults.todoistFilter),
            todoistRefreshMinutes: value(.todoistRefreshMinutes, defaults.todoistRefreshMinutes),
            todoistTokenPresent: value(.todoistTokenPresent, defaults.todoistTokenPresent)
        )
    }
}

public final class SettingsStore: ObservableObject {
    @Published public var settings: FocusSettings {
        didSet {
            if settings != oldValue { save() }
        }
    }

    public let fileURL: URL

    public init(fileURL: URL = FocusPaths.settingsURL) {
        self.fileURL = fileURL
        FocusPaths.ensureDirectory()
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            self.settings = FocusSettings()
            self.isFirstRun = true
            return
        }
        if let decoded = try? JSONCoding.decoder().decode(FocusSettings.self, from: data) {
            self.settings = decoded
            return
        }
        // Keep the unreadable file: it may be worth repairing by hand.
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        NSLog("FocusDeck: settings.json could not be read; kept a copy at %@", backup.lastPathComponent)
        self.settings = FocusSettings()
        self.isFirstRun = true
    }

    public func save() {
        do {
            let data = try JSONCoding.encoder().encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("FocusDeck: cannot save settings: \(error.localizedDescription)")
        }
    }

    /// True when this is the first start (no settings file existed yet).
    public private(set) var isFirstRun = false

    public func reload() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONCoding.decoder().decode(FocusSettings.self, from: data) {
            settings = decoded
        }
    }
}
