import XCTest
@testable import PokeTokenBar

// MARK: SpectatorStore — same QueuedStubURLProtocol/waitUntil pattern as BattleStoreTests.swift

private final class SpectatorQueuedStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    private static let lock = NSLock()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let next = Self.responses.isEmpty ? (200, Data()) : Self.responses.removeFirst()
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

    private func makeStore(pollIntervalNanoseconds: UInt64 = 10_000_000) -> SpectatorStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpectatorQueuedStubURLProtocol.self]
        return SpectatorStore(session: URLSession(configuration: config), pollIntervalNanoseconds: pollIntervalNanoseconds)
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
