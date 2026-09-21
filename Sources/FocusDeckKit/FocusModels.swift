import Foundation

/// Where a focus item came from.
public enum TaskSource: String, Codable, Sendable, CaseIterable {
    case custom
    case todoist
    case agent
}

/// One thing to focus on. This is what the deck shows in big letters.
public struct FocusItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var source: TaskSource
    public var project: String?
    public var detail: String?
    public var startedAt: Date?
    public var coverSeed: UInt64

    /// Longest title the deck shows in big letters. Anything beyond this moves to `detail`,
    /// so a pasted URL or hash cannot push the letters out of the window.
    public static let maxTitleLength = 240

    /// Split an over-long title into a headline and the remainder.
    public static func splitTitle(_ raw: String) -> (title: String, remainder: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxTitleLength else { return (trimmed, nil) }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: maxTitleLength)
        let headline = String(trimmed[..<cut]).trimmingCharacters(in: .whitespaces)
        let rest = String(trimmed[cut...]).trimmingCharacters(in: .whitespaces)
        return (headline + "\u{2026}", rest.isEmpty ? nil : rest)
    }

    /// Tolerant decoding: agents and scripts write this file by hand, so a missing
    /// `coverSeed` (or a wrong type) must not make the whole state unreadable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil ?? ""
        self.title = title
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil ?? UUID().uuidString
        self.source = (try? container.decodeIfPresent(TaskSource.self, forKey: .source)) ?? nil ?? .custom
        self.project = (try? container.decodeIfPresent(String.self, forKey: .project)) ?? nil
        self.detail = (try? container.decodeIfPresent(String.self, forKey: .detail)) ?? nil
        self.startedAt = (try? container.decodeIfPresent(Date.self, forKey: .startedAt)) ?? nil
        let seed = (try? container.decodeIfPresent(UInt64.self, forKey: .coverSeed)) ?? nil
        self.coverSeed = seed ?? CoverCatalog.seed(from: title)
    }

    public init(id: String = UUID().uuidString,
                title: String,
                source: TaskSource = .custom,
                project: String? = nil,
                detail: String? = nil,
                startedAt: Date? = nil,
                coverSeed: UInt64? = nil) {
        let split = FocusItem.splitTitle(title)
        self.id = id
        self.title = split.title
        self.source = source
        self.project = project
        self.detail = detail ?? split.remainder
        self.startedAt = startedAt
        self.coverSeed = coverSeed ?? CoverCatalog.seed(from: split.title)
    }

    /// Seconds spent on this item, if a start time is known.
    public func elapsed(now: Date = Date()) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, now.timeIntervalSince(startedAt))
    }
}

/// A short banner shown on top of the deck (for example: a new agent message).
public struct OverlayMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var subtitle: String?
    public var kind: String        // "info" | "warn" | "agent"
    public var createdAt: Date
    public var ttl: TimeInterval

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? nil ?? ""
        self.id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil ?? UUID().uuidString
        self.subtitle = (try? container.decodeIfPresent(String.self, forKey: .subtitle)) ?? nil
        self.kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil ?? "info"
        self.createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil ?? Date()
        let ttl = (try? container.decodeIfPresent(TimeInterval.self, forKey: .ttl)) ?? nil
        self.ttl = FocusStore.sanitizedOverlayTTL(ttl ?? 12)
    }

    public init(id: String = UUID().uuidString, text: String, subtitle: String? = nil,
                kind: String = "info", createdAt: Date = Date(), ttl: TimeInterval = 12) {
        self.id = id
        self.text = text
        self.subtitle = subtitle
        self.kind = kind
        self.createdAt = createdAt
        self.ttl = ttl
    }

    public func isAlive(now: Date = Date()) -> Bool { now.timeIntervalSince(createdAt) < ttl }
}

/// The whole shared state, stored as JSON so the app, the CLI and agents can all write it.
public struct FocusState: Codable, Equatable, Sendable {
    public var revision: Int
    public var writer: String
    public var updatedAt: Date
    public var current: FocusItem?
    public var queue: [FocusItem]
    public var history: [FocusItem]
    public var overlay: OverlayMessage?
    public var nextTodoistTaskID: String? // Explicit next choice in Focus Deck; does not reorder Todoist.

    /// Tolerant decoding: a partial file still loads, so one bad writer cannot blank the deck.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.revision = (try? container.decodeIfPresent(Int.self, forKey: .revision)) ?? nil ?? 0
        self.writer = (try? container.decodeIfPresent(String.self, forKey: .writer)) ?? nil ?? "unknown"
        self.updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? nil
            ?? Date(timeIntervalSince1970: 0)
        self.current = (try? container.decodeIfPresent(FocusItem.self, forKey: .current)) ?? nil
        self.queue = (try? container.decodeIfPresent([FocusItem].self, forKey: .queue)) ?? nil ?? []
        self.history = (try? container.decodeIfPresent([FocusItem].self, forKey: .history)) ?? nil ?? []
        self.overlay = (try? container.decodeIfPresent(OverlayMessage.self, forKey: .overlay)) ?? nil
        self.nextTodoistTaskID = (try? container.decodeIfPresent(String.self, forKey: .nextTodoistTaskID)) ?? nil
    }

    public init(revision: Int = 0, writer: String = "app", updatedAt: Date = Date(),
                current: FocusItem? = nil, queue: [FocusItem] = [], history: [FocusItem] = [],
                overlay: OverlayMessage? = nil, nextTodoistTaskID: String? = nil) {
        self.revision = revision
        self.writer = writer
        self.updatedAt = updatedAt
        self.current = current
        self.queue = queue
        self.history = history
        self.overlay = overlay
        self.nextTodoistTaskID = nextTodoistTaskID
    }

    public static func empty() -> FocusState { FocusState() }
}
