import XCTest
import Foundation
@testable import FocusDeckKit

// MARK: - Offline network stub

/// Records every request and replays canned answers. No test in this file touches the network.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var body: Data
        init(status: Int = 200, body: Data = Data()) {
            self.status = status
            self.body = body
        }
        init(status: Int, json: String) {
            self.status = status
            self.body = Data(json.utf8)
        }
    }

    struct Recorded {
        var url: URL?
        var method: String?
        var headers: [String: String]
        var body: Data?
    }

    private static let lock = NSLock()
    private static var stubs: [Stub] = []
    private static var records: [Recorded] = []

    static func reset(stubs: [Stub] = []) {
        lock.lock(); defer { lock.unlock() }
        self.stubs = stubs
        self.records = []
    }

    static var recorded: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return records
    }

    static var requestCount: Int { recorded.count }

    private static func next() -> Stub {
        lock.lock(); defer { lock.unlock() }
        if stubs.isEmpty { return Stub(status: 200, json: "{}") }
        return stubs.count == 1 ? stubs[0] : stubs.removeFirst()
    }

    private static func record(_ request: URLRequest) {
        let recorded = Recorded(url: request.url,
                                method: request.httpMethod,
                                headers: request.allHTTPHeaderFields ?? [:],
                                body: drain(request))
        lock.lock(); defer { lock.unlock() }
        records.append(recorded)
    }

    private static func drain(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.record(request)
        let stub = StubURLProtocol.next()
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://api.todoist.com")!,
                                       statusCode: stub.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty { client?.urlProtocol(self, didLoad: stub.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Fixtures

private let fixturesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

private func fixture(_ name: String) throws -> Data {
    let url = fixturesDirectory.appendingPathComponent(name)
    return try Data(contentsOf: url)
}

private func makeClient(stubs: [StubURLProtocol.Stub]) -> TodoistClient {
    StubURLProtocol.reset(stubs: stubs)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    let session = URLSession(configuration: configuration)
    return TodoistClient(token: "test-token", session: session)
}

// MARK: - Decoding (real-shape fixtures)

final class TodoistDecodingTests: XCTestCase {

    func testDecodesPaginatedEnvelope() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        XCTAssertEqual(tasks.count, 5)
        XCTAssertEqual(tasks.map(\.id), [
            "6XGgmFVcrG5RRjVr", "6XGgmFVcrG5RRjVs", "6XGgmFVcrG5RRjVt",
            "6XGgmFVcrG5RRjVu", "7700011223",
        ])
        XCTAssertEqual(TodoistClient.decodeNextCursor(from: try fixture("tasks_page1.json")),
                       "14540000435w8hj8pXXwPQJJch.X9DBH8ya2Xenok55")
    }

    func testDecodesBareArray() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_bare_array.json"))
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.first?.content, "Bare array task A")
        XCTAssertNil(TodoistClient.decodeNextCursor(from: try fixture("tasks_bare_array.json")))
    }

    func testNullDueMeansNoDueLabel() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let unicode = try XCTUnwrap(tasks.first { $0.id == "6XGgmFVcrG5RRjVs" })
        XCTAssertNil(unicode.dueLabel)
        XCTAssertNil(unicode.dueDate)
    }

    func testDueObjectBecomesReadableLabel() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let first = try XCTUnwrap(tasks.first)
        XCTAssertEqual(first.dueLabel, "tomorrow")
        XCTAssertEqual(first.dueDate, "2025-02-12")
    }

    func testDueAsPlainStringIsAccepted() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let plain = try XCTUnwrap(tasks.first { $0.id == "6XGgmFVcrG5RRjVu" })
        XCTAssertEqual(plain.dueLabel, "2025-03-01")
        XCTAssertEqual(plain.dueDate, "2025-03-01")
        XCTAssertEqual(plain.labels, ["work", "review"], "a comma separated label string is tolerated")
    }

    func testMissingAndEmptyDescriptionBecomeNil() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let empty = try XCTUnwrap(tasks.first { $0.id == "6XGgmFVcrG5RRjVt" })
        XCTAssertNil(empty.description, "empty description should not be shown as text")
        let whitespace = try XCTUnwrap(tasks.first { $0.id == "7700011223" })
        XCTAssertNil(whitespace.description)
        let missing = try XCTUnwrap(tasks.first { $0.id == "6XGgmFVcrG5RRjVs" })
        XCTAssertNil(missing.description)
    }

    func testAllFourPrioritiesSurvive() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.priority) })
        XCTAssertEqual(byID["6XGgmFVcrG5RRjVr"], 1)
        XCTAssertEqual(byID["6XGgmFVcrG5RRjVt"], 2)
        XCTAssertEqual(byID["6XGgmFVcrG5RRjVu"], 3)
        XCTAssertEqual(byID["6XGgmFVcrG5RRjVs"], 4)
    }

    func testOutOfRangePriorityIsClamped() throws {
        let data = Data(#"{"results":[{"id":"a","content":"x","priority":9},{"id":"b","content":"y","priority":0}]}"#.utf8)
        let tasks = try TodoistClient.decodeTasks(from: data)
        XCTAssertEqual(tasks.map(\.priority), [4, 1])
    }

    func testStringPriorityAndNumericIDAreTolerated() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let legacy = try XCTUnwrap(tasks.first { $0.id == "7700011223" })
        XCTAssertEqual(legacy.priority, 2, "priority may arrive as a string")
        XCTAssertEqual(legacy.projectID, "990001", "a numeric project id becomes a string")
        XCTAssertEqual(legacy.labels, [])
        XCTAssertFalse(legacy.isCompleted)
    }

    func testUnicodeTextIsPreserved() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let unicode = try XCTUnwrap(tasks.first { $0.id == "6XGgmFVcrG5RRjVs" })
        XCTAssertTrue(unicode.content.contains("молоко"))
        XCTAssertTrue(unicode.content.contains("\u{1F95B}"))
        XCTAssertEqual(unicode.labels, ["shopping", "дом"])
    }

    func testProjectAndSectionIDsAndLabels() throws {
        let tasks = try TodoistClient.decodeTasks(from: try fixture("tasks_page1.json"))
        let first = try XCTUnwrap(tasks.first)
        XCTAssertEqual(first.projectID, "6XGgm6PHrGgMpCFX")
        XCTAssertEqual(first.sectionID, "6fFPHV272WWh3gpW")
        XCTAssertEqual(first.labels, ["priority"])
        XCTAssertFalse(first.isCompleted)
    }

    func testAsFocusItemUsesTodoistPrefix() throws {
        var task = try XCTUnwrap(TodoistClient.decodeTasks(from: try fixture("tasks_page1.json")).first)
        task.projectName = "Inbox"
        let item = task.asFocusItem()
        XCTAssertEqual(item.id, "todoist:6XGgmFVcrG5RRjVr")
        XCTAssertEqual(item.title, "Buy milk")
        XCTAssertEqual(item.source, .todoist)
        XCTAssertEqual(item.project, "Inbox")
        XCTAssertEqual(item.detail, "Pick up organic milk")
    }

    func testAsFocusItemWithNilDetailIsFine() throws {
        let task = TodoistTask(id: "42", content: "No description")
        let item = task.asFocusItem()
        XCTAssertNil(item.detail)
        XCTAssertEqual(item.id, "todoist:42")
    }

    func testProjectsEnvelopeAndBareArray() throws {
        let envelope = try TodoistClient.decodeProjects(from: try fixture("projects_envelope.json"))
        XCTAssertEqual(envelope.map(\.name), ["Inbox", "Работа \u{1F4BC}"])
        XCTAssertEqual(envelope.first?.id, "6XGgm6PHrGgMpCFX")

        let bare = try TodoistClient.decodeProjects(from: try fixture("projects_bare_array.json"))
        XCTAssertEqual(bare.map(\.id), ["6XGgm6PHrGgMpCFX", "6XGgm6PHrGgMpCFZ"])
    }

    func testGarbagePayloadThrowsDecodingError() throws {
        XCTAssertThrowsError(try TodoistClient.decodeTasks(from: Data(#"{"unexpected":true}"#.utf8))) { error in
            guard case TodoistError.decoding = error else {
                return XCTFail("expected a decoding error, got \(error)")
            }
        }
        XCTAssertThrowsError(try TodoistClient.decodeProjects(from: Data("not json".utf8)))
    }

    func testTaskWithoutIDIsRejected() throws {
        XCTAssertThrowsError(try TodoistClient.decodeTasks(from: Data(#"[{"content":"no id"}]"#.utf8)))
    }

    func testRealUnauthorizedBodyIsNotMistakenForATaskList() throws {
        let body = try fixture("error_401.json")
        XCTAssertThrowsError(try TodoistClient.decodeTasks(from: body))
    }
}

// MARK: - Identifier normalisation

final class TodoistIdentifierTests: XCTestCase {
    func testStripsTodoistPrefix() {
        XCTAssertEqual(TodoistClient.normalizedTaskID(from: "todoist:6XGgmFVcrG5RRjVr"), "6XGgmFVcrG5RRjVr")
        XCTAssertEqual(TodoistClient.normalizedTaskID(from: "6XGgmFVcrG5RRjVr"), "6XGgmFVcrG5RRjVr")
        XCTAssertEqual(TodoistClient.normalizedTaskID(from: "  todoist:42  "), "42")
        XCTAssertEqual(TodoistClient.normalizedTaskID(from: "TODOIST:42"), "42")
        XCTAssertEqual(TodoistClient.normalizedTaskID(from: "https://app.todoist.com/app/task/6XGgmFVcrG5RRjVr"),
                       "6XGgmFVcrG5RRjVr")
    }

    func testUnknownShapesAreRejected() {
        XCTAssertNil(TodoistClient.normalizedTaskID(from: ""))
        XCTAssertNil(TodoistClient.normalizedTaskID(from: "   "))
        XCTAssertNil(TodoistClient.normalizedTaskID(from: "todoist:"))
        XCTAssertNil(TodoistClient.normalizedTaskID(from: "custom:abc-123"))
        XCTAssertNil(TodoistClient.normalizedTaskID(from: "agent:whatever"))
        XCTAssertNil(TodoistClient.normalizedTaskID(from: "todoist:../../etc/passwd"))
    }
}

// MARK: - Request building and pagination (stubbed URLProtocol)

final class TodoistRequestTests: XCTestCase {

    private func page(_ ids: [String], cursor: String?) throws -> Data {
        let results = ids.map { ["id": $0, "content": "Task \($0)", "priority": 1] as [String: Any] }
        let object: [String: Any] = ["results": results, "next_cursor": cursor as Any]
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testCompleteBuildsPostToCloseEndpoint() async throws {
        let client = makeClient(stubs: [.init(status: 200, json: "null")])
        try await client.complete(taskID: "todoist:6XGgmFVcrG5RRjVr")

        let request = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.todoist.com/api/v1/tasks/6XGgmFVcrG5RRjVr/close")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-token")
        XCTAssertNil(request.body)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testCompleteAcceptsABareID() async throws {
        let client = makeClient(stubs: [.init(status: 204)])
        try await client.complete(taskID: "42")
        XCTAssertEqual(StubURLProtocol.recorded.first?.url?.absoluteString,
                       "https://api.todoist.com/api/v1/tasks/42/close")
    }

    func testCompleteIsANoOpForUnknownShapes() async throws {
        let client = makeClient(stubs: [.init(status: 200, json: "null")])
        try await client.complete(taskID: "custom:my-custom-task")
        try await client.complete(taskID: "")
        try await client.complete(taskID: "todoist:")
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "unknown ids must not hit the network")
    }

    func testReopenBuildsPostToReopenEndpoint() async throws {
        let client = makeClient(stubs: [.init(status: 200, json: "null")])
        try await client.reopen(taskID: "todoist:6XGgmFVcrG5RRjVr")
        XCTAssertEqual(StubURLProtocol.recorded.first?.method, "POST")
        XCTAssertEqual(StubURLProtocol.recorded.first?.url?.absoluteString,
                       "https://api.todoist.com/api/v1/tasks/6XGgmFVcrG5RRjVr/reopen")
    }

    func testTasksWithoutFilterListsAllTasks() async throws {
        let client = makeClient(stubs: [.init(body: try page(["a"], cursor: nil))])
        _ = try await client.tasks()
        let url = try XCTUnwrap(StubURLProtocol.recorded.first?.url)
        XCTAssertEqual(url.path, "/api/v1/tasks")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "limit" })?.value, "200")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "query" }))
    }

    func testTasksWithFilterUsesTheFilterEndpoint() async throws {
        let client = makeClient(stubs: [.init(body: try page(["a"], cursor: nil))])
        _ = try await client.tasks(filter: "today | overdue")
        let url = try XCTUnwrap(StubURLProtocol.recorded.first?.url)
        XCTAssertEqual(url.path, "/api/v1/tasks/filter")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "query" })?.value, "today | overdue")
        XCTAssertEqual(items.first(where: { $0.name == "limit" })?.value, "200")
    }

    func testBlankFilterFallsBackToListEndpoint() async throws {
        let client = makeClient(stubs: [.init(body: try page(["a"], cursor: nil))])
        _ = try await client.tasks(filter: "   ")
        XCTAssertEqual(StubURLProtocol.recorded.first?.url?.path, "/api/v1/tasks")
    }

    func testCursorPaginationFollowsNextCursor() async throws {
        let client = makeClient(stubs: [
            .init(body: try fixture("tasks_page1.json")),
            .init(body: try fixture("tasks_page2.json")),
        ])
        let tasks = try await client.tasks(filter: "today")

        XCTAssertEqual(tasks.count, 6, "both fixture pages must be collected")
        XCTAssertEqual(tasks.map(\.id), [
            "6XGgmFVcrG5RRjVr", "6XGgmFVcrG5RRjVs", "6XGgmFVcrG5RRjVt",
            "6XGgmFVcrG5RRjVu", "7700011223", "6XGgmFVcrG5RRjVv",
        ])
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
        let second = try XCTUnwrap(StubURLProtocol.recorded.last?.url)
        let items = URLComponents(url: second, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "cursor" })?.value,
                       "14540000435w8hj8pXXwPQJJch.X9DBH8ya2Xenok55")
        XCTAssertEqual(items.first(where: { $0.name == "query" })?.value, "today",
                       "the cursor request must repeat the original filter")
    }

    func testPaginationStopsAtThePageCap() async throws {
        let endless = (0..<12).map { _ in
            StubURLProtocol.Stub(body: (try? page(["a"], cursor: "next.cursor")) ?? Data())
        }
        let client = makeClient(stubs: endless)
        _ = try await client.tasks(maxPages: 3)
        XCTAssertEqual(StubURLProtocol.requestCount, 3)
    }

    func testLimitIsCappedAtTwoHundred() async throws {
        let client = makeClient(stubs: [.init(body: try page(["a"], cursor: nil))])
        _ = try await client.tasks(limit: 5000)
        let url = try XCTUnwrap(StubURLProtocol.recorded.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "limit" })?.value, "200")
    }

    func testProjectsUsesTheProjectsEndpoint() async throws {
        let client = makeClient(stubs: [.init(body: try fixture("projects_envelope.json"))])
        let projects = try await client.projects()
        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(StubURLProtocol.recorded.first?.url?.path, "/api/v1/projects")
    }

    func testQuickAddPostsTextAndDecodesTheCreatedTask() async throws {
        let client = makeClient(stubs: [.init(body: try fixture("quick_add_response.json"))])
        let created = try await client.quickAdd(content: "Buy milk today #Shopping p2")

        let request = try XCTUnwrap(StubURLProtocol.recorded.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/tasks/quick")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        let body = try XCTUnwrap(request.body)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["text"] as? String, "Buy milk today #Shopping p2")

        XCTAssertEqual(created?.id, "6XGgmFVcrG5RRjX1")
        XCTAssertEqual(created?.dueLabel, "today")
        XCTAssertEqual(created?.priority, 2)
        XCTAssertEqual(created?.labels, ["shopping", "groceries"])
    }

    func testQuickAddRejectsEmptyText() async throws {
        let client = makeClient(stubs: [.init(status: 200, json: "{}")])
        do {
            _ = try await client.quickAdd(content: "   ")
            XCTFail("expected emptyInput")
        } catch let error as TodoistError {
            XCTAssertEqual(error, .emptyInput)
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    func testUnauthorizedAnswerBecomesATypedError() async throws {
        let body = try fixture("error_401.json")
        let client = makeClient(stubs: [.init(status: 401, body: body)])
        do {
            _ = try await client.tasks(filter: "today")
            XCTFail("expected an http error")
        } catch let error as TodoistError {
            guard case let .http(status, text) = error else {
                return XCTFail("expected .http, got \(error)")
            }
            XCTAssertEqual(status, 401)
            XCTAssertTrue(text.contains("UNAUTHORIZED"))
            XCTAssertTrue(error.isAuthFailure)
            XCTAssertTrue((error.errorDescription ?? "").contains("401"))
        }
    }

    func testTokenIsValidReflectsTheAnswer() async throws {
        let good = makeClient(stubs: [.init(body: try fixture("projects_envelope.json"))])
        let goodResult = await good.tokenIsValid()
        XCTAssertTrue(goodResult)

        let bad = makeClient(stubs: [.init(status: 401, body: try fixture("error_401.json"))])
        let badResult = await bad.tokenIsValid()
        XCTAssertFalse(badResult)
    }

    func testTokenIsSentOnEveryRequest() async throws {
        let client = makeClient(stubs: [
            .init(body: try page(["a"], cursor: nil)),
            .init(body: try fixture("projects_envelope.json")),
        ])
        _ = try await client.tasks()
        _ = try await client.projects()
        for request in StubURLProtocol.recorded {
            XCTAssertEqual(request.headers["Authorization"], "Bearer test-token")
        }
    }

    func testTransportFailureIsReportedAsTransportError() async throws {
        StubURLProtocol.reset(stubs: [])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingURLProtocol.self]
        let client = TodoistClient(token: "t", session: URLSession(configuration: configuration))
        do {
            _ = try await client.tasks()
            XCTFail("expected a transport error")
        } catch let error as TodoistError {
            guard case .transport = error else { return XCTFail("expected .transport, got \(error)") }
        }
    }
}

/// Always fails, to exercise the transport error path.
final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
