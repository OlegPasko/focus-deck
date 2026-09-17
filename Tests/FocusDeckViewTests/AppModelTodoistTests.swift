import XCTest
import Foundation
import FocusDeckKit
@testable import FocusDeck

@MainActor
final class AppModelTodoistTests: XCTestCase {
    private var directory: URL!
    private var model: AppModel!
    private var session: URLSession!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CreationProtocol.self]
        session = URLSession(configuration: config)
        CreationProtocol.reset()
        let client = TodoistClient(token: "test-token", session: session)
        let settings = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        settings.settings.todoistEnabled = false
        model = AppModel(store: FocusStore(fileURL: directory.appendingPathComponent("focus.json"), writerName: "test"),
                         settings: settings, loadCredentials: false, makeTodoistClient: { client })
        model.store.setFocus(title: "Original focus", itemID: "original")
        model.draftTitle = "Review tomorrow's plan #literally + A&B – Перевірка"
        model.isEditingFocus = true
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        model = nil
        try FileManager.default.removeItem(at: directory)
    }

    func testCreateForTodayThenCompleteTheSameTodoistTask() async throws {
        await model.applyDraft()?.value
        XCTAssertEqual(model.store.state.current?.id, "todoist:created-42")
        XCTAssertEqual(model.store.state.current?.source, .todoist)
        XCTAssertEqual(model.store.state.current?.title, "Review tomorrow's plan #literally + A&B – Перевірка")
        XCTAssertFalse(model.isEditingFocus)
        XCTAssertEqual(model.draftTitle, "")
        XCTAssertNil(model.draftError)
        let command = try XCTUnwrap(CreationProtocol.commands.first)
        let args = try XCTUnwrap(command["args"] as? [String: Any])
        XCTAssertEqual(args["content"] as? String, "Review tomorrow's plan #literally + A&B – Перевірка")
        XCTAssertNil(args["project_id"], "New tasks belong to Inbox")
        let due = try XCTUnwrap(args["due"] as? [String: String])
        let date = try XCTUnwrap(due["date"])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertTrue(Calendar.current.isDateInToday(try XCTUnwrap(formatter.date(from: date))))
        let persisted = FocusStore(fileURL: directory.appendingPathComponent("focus.json"), writerName: "reader")
        XCTAssertEqual(persisted.state.current?.id, "todoist:created-42")

        await model.completeCurrent()?.value
        XCTAssertTrue(CreationProtocol.paths.contains("/api/v1/tasks/created-42/close"))
        XCTAssertNil(model.store.state.current)
        XCTAssertFalse(model.isCompleting)
    }

    func testLaterUsesTodayInsteadOfLocalQueueOrPicker() async {
        model.store.setFocus(title: "Current", source: .todoist, itemID: "todoist:current")
        model.store.setQueue([FocusItem(title: "Old local queue")])
        model.todoistTasks = [TodoistTask(id: "future", content: "Tomorrow")]
        model.settings.settings.todoistFilter = "all"
        CreationProtocol.today = [
            ["id": "current", "content": "Current"],
            ["id": "next", "content": "Next from Today"],
            ["id": "last", "content": "Last from Today"]
        ]
        await model.refreshToday()
        XCTAssertEqual(model.laterText, "Next from Today")
        XCTAssertEqual(CreationProtocol.filters, ["today"])
        XCTAssertEqual(model.store.state.current?.id, "todoist:current")
        XCTAssertEqual(model.todoistTasks.first?.id, "future")
    }

    func testCompletionAdvancesToNextTodayAndThenShowsEndOfDay() async {
        await model.applyDraft()?.value
        model.store.setQueue([FocusItem(title: "Ignore the old queue")])
        CreationProtocol.today = [["id": "next", "content": "Next from Today"]]
        await model.completeCurrent()?.value
        XCTAssertEqual(model.store.state.current?.id, "todoist:next")
        XCTAssertEqual(model.laterText, "No more tasks for today")
        CreationProtocol.today = []
        await model.completeCurrent()?.value
        XCTAssertNil(model.store.state.current)
        XCTAssertEqual(model.emptyFocusText, "No more tasks for today")
        XCTAssertEqual(model.laterText, "No more tasks for today")
        XCTAssertTrue(CreationProtocol.paths.contains("/api/v1/tasks/next/close"))
    }

    func testFailedTodayFetchDoesNotClaimDayIsFinishedAndRefreshRetries() async {
        await model.applyDraft()?.value
        CreationProtocol.failToday = true
        await model.completeCurrent()?.value
        XCTAssertNil(model.store.state.current, "Remote completion succeeded")
        XCTAssertNotNil(model.todayError)
        XCTAssertEqual(model.emptyFocusText, "Could not load today’s tasks")
        XCTAssertEqual(model.laterText, "Could not load today’s tasks")
        CreationProtocol.failToday = false
        CreationProtocol.today = [["id": "retry", "content": "Loaded after retry"]]
        await model.refreshToday()
        XCTAssertEqual(model.store.state.current?.id, "todoist:retry")
        XCTAssertNil(model.todayError)
        XCTAssertEqual(CreationProtocol.paths.filter { $0.hasSuffix("/close") }.count, 1)
    }

    func testCompletionAndAdvancePreserveAnotherWritersFocus() async {
        await model.applyDraft()?.value
        CreationProtocol.today = [["id": "next", "content": "Next from Today"]]
        let completion = model.completeCurrent()
        let other = FocusStore(fileURL: directory.appendingPathComponent("focus.json"), writerName: "agent")
        other.setFocus(title: "New focus", itemID: "newer")
        await completion?.value
        XCTAssertEqual(model.store.state.current?.id, "newer")
    }

    func testRetryDoesNotOverwriteFocusChosenWhileTodayWasUnavailable() async {
        await model.applyDraft()?.value
        CreationProtocol.failToday = true
        await model.completeCurrent()?.value
        let other = FocusStore(fileURL: directory.appendingPathComponent("focus.json"), writerName: "agent")
        other.setFocus(title: "New focus", itemID: "newer")
        CreationProtocol.failToday = false
        CreationProtocol.today = [["id": "next", "content": "Next from Today"]]
        await model.refreshToday()
        XCTAssertEqual(model.store.state.current?.id, "newer")
    }

    func testCompletedAndJustFinishedTasksAreNotSelectedAgain() async {
        await model.applyDraft()?.value
        CreationProtocol.today = [
            ["id": "created-42", "content": "Stale just-finished task"],
            ["id": "closed", "content": "Already done", "is_completed": true],
            ["id": "next", "content": "Still open"]
        ]
        await model.completeCurrent()?.value
        XCTAssertEqual(model.store.state.current?.id, "todoist:next")
    }

    func testRepeatedSubmitCreatesOnlyOnce() async {
        let first = model.applyDraft()
        XCTAssertTrue(model.isCreatingTask)
        XCTAssertNil(model.applyDraft())
        await first?.value
        XCTAssertEqual(CreationProtocol.commands.count, 1)
    }

    func testMissingCredentialsPreservesDraftAndCurrentFocus() async {
        let noToken = AppModel(store: model.store, settings: model.settings, loadCredentials: false,
                               makeTodoistClient: { nil })
        noToken.draftTitle = "New task"
        noToken.isEditingFocus = true
        await noToken.applyDraft()?.value
        XCTAssertEqual(noToken.store.state.current?.id, "original")
        XCTAssertEqual(noToken.draftTitle, "New task")
        XCTAssertTrue(noToken.isEditingFocus)
        XCTAssertNotNil(noToken.draftError)
        XCTAssertTrue(CreationProtocol.paths.isEmpty)
    }

    func testCreationRejectionKeepsDraftAndDoesNotCreateLocalTask() async {
        CreationProtocol.rejectCreation = true
        await model.applyDraft()?.value
        XCTAssertEqual(model.store.state.current?.id, "original")
        XCTAssertEqual(model.draftTitle, "Review tomorrow's plan #literally + A&B – Перевірка")
        XCTAssertTrue(model.isEditingFocus)
        XCTAssertNotNil(model.draftError)
        XCTAssertFalse(model.isCreatingTask)
        XCTAssertEqual(CreationProtocol.paths, ["/api/v1/sync"])
    }

    func testRetryAfterLostTaskResponseUsesTheSameCreationUUID() async {
        CreationProtocol.failTaskReadOnce = true
        await model.applyDraft()?.value
        XCTAssertNotNil(model.draftError)
        XCTAssertEqual(model.store.state.current?.id, "original")
        await model.applyDraft()?.value
        XCTAssertEqual(CreationProtocol.commands.count, 2)
        XCTAssertEqual(CreationProtocol.commands[0]["uuid"] as? String,
                       CreationProtocol.commands[1]["uuid"] as? String)
        XCTAssertEqual(model.store.state.current?.id, "todoist:created-42")
        XCTAssertNil(model.draftError)
    }

    func testAnotherWritersFocusIsPreservedWhileCreatedTaskIsQueued() async {
        let creation = model.applyDraft()
        let other = FocusStore(fileURL: directory.appendingPathComponent("focus.json"), writerName: "agent")
        other.setFocus(title: "A newer focus", itemID: "newer")
        await creation?.value
        XCTAssertEqual(model.store.state.current?.id, "newer")
        XCTAssertEqual(model.store.state.queue.map(\.id), ["todoist:created-42"])
    }

    func testCompletionFailureKeepsLinkedTaskOpenLocally() async {
        await model.applyDraft()?.value
        CreationProtocol.failCompletion = true
        await model.completeCurrent()?.value
        XCTAssertEqual(model.store.state.current?.id, "todoist:created-42")
        XCTAssertEqual(model.store.state.overlay?.text, "Could not complete the Todoist task")
        XCTAssertFalse(model.isCompleting)
    }

    func testReapplyingAnUnchangedLinkedFocusDoesNotDuplicateIt() async {
        await model.applyDraft()?.value
        model.draftTitle = model.store.state.current!.title
        await model.applyDraft()?.value
        XCTAssertEqual(CreationProtocol.commands.count, 1)
    }
}

/// Isolated HTTP fake; these tests never access the Keychain or a real Todoist account.
private final class CreationProtocol: URLProtocol {
    static var commands: [[String: Any]] = []
    static var paths: [String] = []
    static var rejectCreation = false
    static var failTaskReadOnce = false
    static var failCompletion = false
    static var today: [[String: Any]] = []
    static var failToday = false
    static var filters: [String] = []
    private static var title = ""
    private static var dueDate = ""

    static func reset() {
        commands = []; paths = []; rejectCreation = false
        failTaskReadOnce = false; failCompletion = false
        today = []; failToday = false; filters = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url!.path
        Self.paths.append(path)
        var status = 200
        var object: [String: Any] = [:]
        if path == "/api/v1/sync" {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
            }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            var form = URLComponents()
            form.percentEncodedQuery = String(decoding: data, as: UTF8.self)
            let json = form.queryItems!.first { $0.name == "commands" }!.value!
            let command = (try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]])[0]
            Self.commands.append(command)
            let key = command["uuid"] as! String
            let tempID = command["temp_id"] as! String
            let args = command["args"] as! [String: Any]
            Self.title = args["content"] as! String
            Self.dueDate = (args["due"] as! [String: String])["date"]!
            if Self.rejectCreation {
                object = ["sync_status": [key: ["error": "Rejected", "http_code": 403]]]
            } else {
                object = ["sync_status": [key: "ok"], "temp_id_mapping": [tempID: "created-42"]]
            }
        } else if path == "/api/v1/tasks/filter" {
            Self.filters.append(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "query" }!.value!)
            status = Self.failToday ? 503 : 200
            object = ["results": Self.today]
        } else if path.hasSuffix("/close") {
            status = Self.failCompletion ? 503 : 204
        } else if path == "/api/v1/tasks/created-42" {
            if Self.failTaskReadOnce {
                Self.failTaskReadOnce = false
                status = 503
            } else {
                object = ["id": "created-42", "content": Self.title, "due": ["date": Self.dueDate]]
            }
        } else { status = 404 }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocolDidFinishLoading(self)
    }
}
