import Foundation

/// Where Focus Deck keeps its files.
public enum FocusPaths {
    /// Override the folder with `FOCUSDECK_HOME`. Tests and scripts use this so they never
    /// touch the real deck state.
    public static var appSupport: URL {
        if let override = ProcessInfo.processInfo.environment["FOCUSDECK_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FocusDeck", isDirectory: true)
    }

    public static var stateURL: URL { appSupport.appendingPathComponent("focus.json") }
    public static var settingsURL: URL { appSupport.appendingPathComponent("settings.json") }
    public static var logURL: URL { appSupport.appendingPathComponent("focusdeck.log") }

    public static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }
}

public enum JSONCoding {
    public static func encoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
