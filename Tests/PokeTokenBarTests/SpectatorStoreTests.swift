import XCTest
@testable import PokeTokenBar

// MARK: SpectatorStore — same QueuedStubURLProtocol/waitUntil pattern as BattleStoreTests.swift

private final class SpectatorQueuedStubURLProtocol: URLProtocol {
    /// Queues are per store (keyed by a session header), so a stopped store's in-flight request can
    /// no longer take the next test's response. That theft left CI stores stuck on `.connecting`.
    nonisolated(unsafe) private static var queues: [String: [(Int, Data)]] = [:]
    nonisolated(unsafe) static var currentKey = ""
    static let header = "X-Stub-Queue"
    private static let lock = NSLock()
    static var responses: [(Int, Data)] {
        get { lock.lock(); defer { lock.unlock() }; return queues[currentKey] ?? [] }
        set { lock.lock(); queues[currentKey] = newValue; lock.unlock() }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.value(forHTTPHeaderField: Self.header) ?? ""
        Self.lock.lock()
        var queue = Self.queues[key] ?? []
        let next = queue.isEmpty ? (200, Data()) : queue.removeFirst()
        Self.queues[key] = queue
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class SpectatorStoreTests: XCTestCase {
    private func waitUntil(timeout: TimeInterval = 4, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// 스텁 응답 큐는 **정적 공유 상태**다. 이전 테스트가 남긴 스토어가 10ms 마다 계속 폴하면서 다음 테스트가
    /// 넣은 응답을 먼저 `removeFirst()` 해 가고, 그 테스트의 스토어는 빈 본문을 받아 `.connecting` 에 멈춘다 —
    /// CI 에서만 간헐적으로 실패한 원인(main fac7ea0 포함, 로컬은 통과). 네 테스트 중 스토어를 멈추는 건
    /// 하나뿐이었다. 그래서 여기서 만든 스토어는 **전부** 테스트 끝에 멈추고, 큐는 테스트마다 비운다.
    override func setUp() async throws {
        SpectatorQueuedStubURLProtocol.currentKey = UUID().uuidString
    }

    private func makeStore(pollIntervalNanoseconds: UInt64 = 10_000_000) -> SpectatorStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpectatorQueuedStubURLProtocol.self]
        config.httpAdditionalHeaders = [SpectatorQueuedStubURLProtocol.header: SpectatorQueuedStubURLProtocol.currentKey]
        let store = SpectatorStore(session: URLSession(configuration: config), pollIntervalNanoseconds: pollIntervalNanoseconds)
        addTeardownBlock { @MainActor in store.stop() }
        return store
    }

    func testStartTransitionsThroughConnectingToWatching() async {
        SpectatorQueuedStubURLProtocol.responses = [
            (200, Data("""
            {"status":"active","turn":1,
             "p1":{"displayName":"Ash","active":{"speciesID":25,"name":"Ash-0","fainted":false,"hpFraction":1},"rosterSize":1},
             "p2":{"displayName":"Gary","active":{"speciesID":4,"name":"Gary-0","fainted":false,"hpFraction":1},"rosterSize":1},
             "log":[]}
            """.utf8)),
        ]
        let store = makeStore()
        store.start(serverURL: "https://mock.test", sessionId: "sess-1")
        XCTAssertEqual(store.phase, .connecting)

        let reachedWatching = await waitUntil {
            if case .watching = store.phase { return true }
            return false
        }
        XCTAssertTrue(reachedWatching)
        guard case .watching(let sessionId, let view) = store.phase else {
            return XCTFail("expected watching, got \(store.phase)")
        }
        XCTAssertEqual(sessionId, "sess-1")
        XCTAssertEqual(view.p1?.displayName, "Ash")
    }

    /// A pre-join 409 ("battle not started") isn't fatal — same "keep polling" shape a transient
    /// network error already gets, since a join can land on any future poll.
    func testPreJoin409DoesNotFailAndKeepsPolling() async {
        SpectatorQueuedStubURLProtocol.responses = [
            (409, Data(#"{"error":"battle not started"}"#.utf8)),
            (200, Data(#"{"status":"active","turn":1,"log":[]}"#.utf8)),
        ]
        let store = makeStore()
        store.start(serverURL: "https://mock.test", sessionId: "sess-1")

        let reachedWatching = await waitUntil {
            if case .watching = store.phase { return true }
            return false
        }
        XCTAssertTrue(reachedWatching, "a pre-join 409 should retry rather than fail")
    }

    /// 404 is terminal — same rule every other session poll in this app follows.
    func testMissingSessionFailsWith404() async {
        SpectatorQueuedStubURLProtocol.responses = [(404, Data(#"{"error":"not found"}"#.utf8))]
        let store = makeStore()
        store.start(serverURL: "https://mock.test", sessionId: "gone")

        let failed = await waitUntil {
            if case .failed(.server(status: 404)) = store.phase { return true }
            return false
        }
        XCTAssertTrue(failed)
    }

    func testStopReturnsToIdleAndStopsPolling() async {
        SpectatorQueuedStubURLProtocol.responses = [(200, Data(#"{"status":"active","turn":1,"log":[]}"#.utf8))]
        let store = makeStore()
        store.start(serverURL: "https://mock.test", sessionId: "sess-1")
        _ = await waitUntil {
            if case .watching = store.phase { return true }
            return false
        }
        store.stop()
        XCTAssertEqual(store.phase, .idle)
    }
}
