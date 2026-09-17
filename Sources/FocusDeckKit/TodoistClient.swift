import Foundation

// MARK: - Models

/// One Todoist task, flattened to what the deck needs.
///
/// Decoding is deliberately tolerant: the Todoist API answers with string ids, but
/// older payloads may carry numbers, `due` may be `null`, a string, or an object,
/// `priority` may arrive as a string, and `description` is often an empty string.
public struct TodoistTask: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var content: String
    public var description: String?
    public var projectID: String?
    public var projectName: String?
    public var sectionID: String?
    public var dueLabel: String?
    public var dueDate: String?
    public var priority: Int              // 1 = normal ... 4 = urgent
    public var labels: [String]
    public var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case description
        case projectID = "project_id"
        case projectName
        case sectionID = "section_id"
        case dueLabel
        case dueDate
        case priority
        case labels
        case isCompleted
        // Decode-only aliases used by the tolerant reader.
        case due
        case checked
        case isCompletedSnake = "is_completed"
        case completed
    }

    public init(id: String,
                content: String,
                description: String? = nil,
                projectID: String? = nil,
                projectName: String? = nil,
                sectionID: String? = nil,
                dueLabel: String? = nil,
                dueDate: String? = nil,
                priority: Int = 1,
                labels: [String] = [],
                isCompleted: Bool = false) {
        self.id = id
        self.content = content
        self.description = description
        self.projectID = projectID
        self.projectName = projectName
        self.sectionID = sectionID
        self.dueLabel = dueLabel
        self.dueDate = dueDate
        self.priority = priority
        self.labels = labels
        self.isCompleted = isCompleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let rawID = container.flexibleString(.id), !rawID.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "task without an id"))
        }
        self.id = rawID
        self.content = container.flexibleString(.content) ?? ""
        self.description = TodoistTask.cleaned(container.flexibleString(.description))
        self.projectID = container.flexibleString(.projectID).flatMap { $0.isEmpty ? nil : $0 }
        self.sectionID = container.flexibleString(.sectionID).flatMap { $0.isEmpty ? nil : $0 }
        self.priority = TodoistTask.clampedPriority(container.flexibleInt(.priority))

        if let raw = container.flexibleStringArray(.labels) {
            self.labels = raw.filter { !$0.isEmpty }
        } else {
            self.labels = []
        }

        let due = try? container.decodeIfPresent(TodoistDue.self, forKey: .due)
        if let due {
            self.dueLabel = TodoistTask.cleaned(due.string ?? due.date ?? due.datetime)
            self.dueDate = due.date ?? due.datetime
        } else if let raw = container.flexibleString(.due), !raw.isEmpty {
            // Some payloads answer with a plain date string instead of an object.
            self.dueLabel = raw
            self.dueDate = raw
        } else {
            self.dueLabel = nil
            self.dueDate = nil
        }

        if let checked = container.flexibleBool(.checked) {
            self.isCompleted = checked
        } else if let checked = container.flexibleBool(.isCompletedSnake) {
            self.isCompleted = checked
        } else if let checked = container.flexibleBool(.completed) {
            self.isCompleted = checked
        } else {
            self.isCompleted = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encodeIfPresent(sectionID, forKey: .sectionID)
        try container.encodeIfPresent(dueLabel, forKey: .dueLabel)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(labels, forKey: .labels)
        try container.encode(isCompleted, forKey: .isCompleted)
    }

    /// Convert to a focus item so the deck can show it.
    public func asFocusItem() -> FocusItem {
        FocusItem(id: "todoist:\(id)", title: content, source: .todoist,
                  project: projectName, detail: description, startedAt: Date())
    }

    // MARK: - Tolerant helpers

    static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func clampedPriority(_ value: Int?) -> Int {
        guard let value else { return 1 }
        return min(4, max(1, value))
    }
}

/// Todoist `due` object: `{date, string, is_recurring, datetime, lang}`.
struct TodoistDue: Decodable, Equatable, Sendable {
    var date: String?
    var string: String?
    var datetime: String?
    var isRecurring: Bool?
    var lang: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = container.flexibleString(.date)
        self.string = container.flexibleString(.string)
        self.datetime = container.flexibleString(.datetime)
        self.isRecurring = container.flexibleBool(.isRecurring)
        self.lang = container.flexibleString(.lang)
    }

    enum CodingKeys: String, CodingKey {
        case date, string, datetime, lang
        case isRecurring = "is_recurring"
    }
}

/// One Todoist project.
public struct TodoistProject: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) { self.id = id; self.name = name }

    enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.flexibleString(.id), !rawID.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "project without an id"))
        }
        self.id = rawID
        self.name = container.flexibleString(.name) ?? rawID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

/// One page of a cursor-paginated Todoist answer.
public struct TodoistPage<Element: Decodable & Sendable>: Sendable {
    public var items: [Element]
    public var nextCursor: String?

    public init(items: [Element], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public var hasMore: Bool { nextCursor?.isEmpty == false }
}

// MARK: - Errors

public enum TodoistError: Error, LocalizedError, Equatable {
    case missingToken
    case emptyInput
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No Todoist API token. Add one in Focus Deck settings."
        case .emptyInput:
            return "Nothing to send to Todoist."
        case let .http(status, body):
            switch status {
            case 401: return "Todoist rejected the token (HTTP 401). Paste a fresh API token in settings."
            case 403: return "Todoist refused the request (HTTP 403). Check the token and its scopes."
            case 429: return "Todoist rate limit hit (HTTP 429). Focus Deck will retry later."
            default: return "Todoist error HTTP \(status): \(body.prefix(200))"
            }
        case let .decoding(message):
            return "Cannot read the Todoist answer: \(message)"
        case let .transport(message):
            return "Network problem: \(message)"
        }
    }

    /// True when the token itself was refused.
    public var isAuthFailure: Bool {
        if case let .http(status, _) = self { return status == 401 || status == 403 }
        return false
    }
}

// MARK: - Client

/// Minimal Todoist API v1 client.
///
/// Verified against <https://developer.todoist.com/api/v1/> (see `docs/todoist.md`):
/// base `https://api.todoist.com/api/v1`, auth header `Authorization: Bearer <token>`,
/// cursor pagination with the `{results, next_cursor}` envelope.
public final class TodoistClient {
    public static let baseURL = URL(string: "https://api.todoist.com/api/v1")!

    /// Maximum number of pages followed per call. 5 pages x 200 items = 1000 items.
    public static let defaultMaxPages = 5
    /// Maximum value accepted by the API for `limit`.
    public static let maxLimit = 200

    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public convenience init?() {
        guard let token = KeychainStore.todoistToken else { return nil }
        self.init(token: token)
    }

    // MARK: - Decoding helpers (pure, unit-testable)

    /// Decode a task list from an envelope (`{"results":[...],"next_cursor":...}`)
    /// or from a bare array.
    public static func decodeTasks(from data: Data) throws -> [TodoistTask] {
        try decodePage(TodoistTask.self, from: data).items
    }

    /// Decode a project list from an envelope or from a bare array.
    public static func decodeProjects(from data: Data) throws -> [TodoistProject] {
        try decodePage(TodoistProject.self, from: data).items
    }

    /// Read the cursor of a paginated answer. Returns nil for a bare array or a null cursor.
    public static func decodeNextCursor(from data: Data) -> String? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(CursorEnvelope.self, from: data) else { return nil }
        guard let cursor = envelope.nextCursor, !cursor.isEmpty else { return nil }
        return cursor
    }

    /// Decode any paginated Todoist answer into items plus the next cursor.
    public static func decodePage<Element: Decodable & Sendable>(_ type: Element.Type,
                                                                from data: Data) throws -> TodoistPage<Element> {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(ResultsEnvelope<Element>.self, from: data) {
            let cursor = envelope.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
            return TodoistPage(items: envelope.results, nextCursor: cursor)
        }
        if let array = try? decoder.decode([Element].self, from: data) {
            return TodoistPage(items: array, nextCursor: nil)
        }
        if let envelope = try? decoder.decode(ItemsEnvelope<Element>.self, from: data) {
            // Legacy sync style payload: {"items": [...]}. Only accept it when the key is
            // really there, so an error body such as {"error":"Unauthorized"} still fails.
            if let list = envelope.items ?? envelope.results {
                let cursor = envelope.nextCursor.flatMap { $0.isEmpty ? nil : $0 }
                return TodoistPage(items: list, nextCursor: cursor)
            }
        }
        throw TodoistError.decoding("unexpected payload: neither a results envelope nor an array")
    }

    private struct ResultsEnvelope<Element: Decodable>: Decodable {
        let results: [Element]
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case results, nextCursor = "next_cursor" }
    }

    private struct ItemsEnvelope<Element: Decodable>: Decodable {
        let items: [Element]?
        let results: [Element]?
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case items, results, nextCursor = "next_cursor" }
    }

    private struct CursorEnvelope: Decodable {
        let nextCursor: String?
        enum CodingKeys: String, CodingKey { case nextCursor = "next_cursor" }
    }

    // MARK: - Identifier handling

    /// Normalise an item id that comes from the UI.
    ///
    /// The app stores Todoist items as `"todoist:<id>"`. A bare id is accepted as is.
    /// Anything with a different scheme (`"custom:..."`, `"agent:..."`) or an unusable
    /// shape returns nil so callers can treat the call as a no-op.
    public static func normalizedTaskID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var value = trimmed
        if let colon = trimmed.firstIndex(of: ":") {
            let scheme = trimmed[trimmed.startIndex..<colon].lowercased()
            switch scheme {
            case "todoist":
                value = String(trimmed[trimmed.index(after: colon)...])
            case "https", "http":
                // Tolerate a pasted task URL such as https://app.todoist.com/app/task/<id>
                let remainder = String(trimmed[trimmed.index(after: colon)...])
                guard let slash = remainder.lastIndex(of: "/") else { return nil }
                value = String(remainder[remainder.index(after: slash)...])
            default:
                return nil
            }
        }

        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard cleaned.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return cleaned
    }

    // MARK: - Requests

    /// Active tasks. With a filter string this uses `/tasks/filter?query=...`,
    /// otherwise it lists every active task.
    ///
    /// - Parameter filter: Todoist filter syntax, for example `today`, `overdue`,
    ///   `##Work` or `@errand & today`.
    public func tasks(filter: String? = nil,
                      limit: Int = TodoistClient.maxLimit,
                      maxPages: Int = TodoistClient.defaultMaxPages) async throws -> [TodoistTask] {
        let query = filter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = query.isEmpty ? "tasks" : "tasks/filter"
        var items: [URLQueryItem] = []
        if !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        return try await paged(TodoistTask.self, path: path, query: items, limit: limit, maxPages: maxPages)
    }

    /// All active projects.
    public func projects(limit: Int = TodoistClient.maxLimit,
                         maxPages: Int = TodoistClient.defaultMaxPages) async throws -> [TodoistProject] {
        try await paged(TodoistProject.self, path: "projects", query: [], limit: limit, maxPages: maxPages)
    }

    /// Close (complete) a task. Non-Todoist ids are ignored instead of throwing.
    public func complete(taskID: String) async throws {
        guard let id = TodoistClient.normalizedTaskID(from: taskID) else { return }
        _ = try await post(path: "tasks/\(id)/close")
    }

    /// Reopen a previously completed task. Non-Todoist ids are ignored instead of throwing.
    public func reopen(taskID: String) async throws {
        guard let id = TodoistClient.normalizedTaskID(from: taskID) else { return }
        _ = try await post(path: "tasks/\(id)/reopen")
    }

    /// Create a task from natural language text (Quick Add).
    /// Returns the created task when the answer can be decoded.
    @discardableResult
    public func quickAdd(content: String) async throws -> TodoistTask? {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TodoistError.emptyInput }
        let body = try JSONSerialization.data(withJSONObject: ["text": text])
        let data = try await post(path: "tasks/quick", body: body)
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(TodoistTask.self, from: data)
    }

    /// Create in Inbox with an explicit date, preserving the title literally.
    /// Sync command UUIDs make retries safe if the server created the task but the reply was lost.
    public func createTask(content: String, dueDate: String, requestID: UUID) async throws -> TodoistTask {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TodoistError.emptyInput }
        let key = requestID.uuidString
        let commands = try JSONSerialization.data(withJSONObject: [[
            "type": "item_add", "uuid": key, "temp_id": key,
            "args": ["content": text, "due": ["date": dueDate]]
        ]])
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = String(decoding: commands, as: UTF8.self).addingPercentEncoding(withAllowedCharacters: safe) else {
            throw TodoistError.transport("could not encode task creation")
        }
        let data = try await post(path: "sync", body: Data("commands=\(encoded)".utf8),
                                  contentType: "application/x-www-form-urlencoded")
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statuses = response["sync_status"] as? [String: Any] else {
            throw TodoistError.decoding("missing creation status")
        }
        guard statuses[key] as? String == "ok" else {
            let failure = statuses[key] as? [String: Any]
            throw TodoistError.http(status: (failure?["http_code"] as? Int) ?? 400,
                                    body: failure?["error"] as? String ?? "Todoist did not confirm task creation")
        }
        guard let mapping = response["temp_id_mapping"] as? [String: String],
              let id = mapping[key], !id.isEmpty,
              Self.normalizedTaskID(from: id) == id else {
            throw TodoistError.decoding("missing created task ID; retry to recover the same task")
        }
        let taskData = try await get(path: "tasks/\(id)", query: [])
        do { return try JSONDecoder().decode(TodoistTask.self, from: taskData) }
        catch { throw TodoistError.decoding("could not read the created task; retry to recover it") }
    }

    /// Cheap token check: one project page.
    public func tokenIsValid() async -> Bool {
        do {
            _ = try await projects(limit: 1, maxPages: 1)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private transport

    private func paged<Element: Decodable & Sendable>(_ type: Element.Type,
                                                      path: String,
                                                      query: [URLQueryItem],
                                                      limit: Int,
                                                      maxPages: Int) async throws -> [Element] {
        let pageLimit = min(TodoistClient.maxLimit, max(1, limit))
        let pageCap = max(1, maxPages)
        var collected: [Element] = []
        var cursor: String? = nil
        var pages = 0

        while pages < pageCap {
            var items = query
            items.append(URLQueryItem(name: "limit", value: String(pageLimit)))
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await get(path: path, query: items)
            let page = try TodoistClient.decodePage(type, from: data)
            collected.append(contentsOf: page.items)
            pages += 1
            guard let next = page.nextCursor else { break }
            cursor = next
        }
        return collected
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: TodoistClient.baseURL, resolvingAgainstBaseURL: false) else {
            throw TodoistError.transport("bad base URL")
        }
        components.path = components.path + "/" + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw TodoistError.transport("bad URL for \(path)") }
        return url
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = "GET"
        decorate(&request)
        return try await perform(request)
    }

    private func post(path: String, body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path, query: []))
        request.httpMethod = "POST"
        decorate(&request)
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    private func decorate(_ request: inout URLRequest) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TodoistError.transport("no HTTP answer")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw TodoistError.http(status: http.statusCode,
                                        body: String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let error as TodoistError {
            throw error
        } catch {
            throw TodoistError.transport(error.localizedDescription)
        }
    }
}

// MARK: - Flexible keyed decoding

extension KeyedDecodingContainer {
    /// Read a value that may be a string, a number or a bool.
    func flexibleString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    /// Read an integer that may arrive as a number or as a string.
    func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        return nil
    }

    func flexibleBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return ["true", "1", "yes"].contains(value.lowercased())
        }
        return nil
    }

    /// Read a list of strings; also accepts a single comma-separated string.
    func flexibleStringArray(_ key: Key) -> [String]? {
        if let value = try? decodeIfPresent([String].self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }
}
