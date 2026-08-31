import XCTest
@testable import PokeTokenBar

// MARK: BattleDeepLink

final class BattleDeepLinkTests: XCTestCase {
    func testParsesValidLink() {
        let url = URL(string: "poketokenbar://battle?server=https%3A%2F%2Fx.example.com%3A3000&session=abc123")!
        let link = BattleDeepLink(url: url)
        XCTAssertEqual(link?.server, "https://x.example.com:3000")
        XCTAssertEqual(link?.sessionId, "abc123")
    }

    func testRejectsWrongSchemeOrHost() {
        XCTAssertNil(BattleDeepLink(url: URL(string: "https://battle?server=x&session=y")!))
        XCTAssertNil(BattleDeepLink(url: URL(string: "poketokenbar://trade?server=x&session=y")!))
    }

    func testRejectsMissingOrEmptyParams() {
        XCTAssertNil(BattleDeepLink(url: URL(string: "poketokenbar://battle?server=x")!))
        XCTAssertNil(BattleDeepLink(url: URL(string: "poketokenbar://battle?server=&session=y")!))
    }

    func testPastedTextAcceptsTheRawDeepLinkOnly() {
        let link = BattleDeepLink(pastedText: "  poketokenbar://battle?server=https%3A%2F%2Fx.example.com&session=abc123  ")
        XCTAssertEqual(link?.server, "https://x.example.com")
        XCTAssertEqual(link?.sessionId, "abc123")
        // No /b/:id landing page exists yet (battles.md M3) — a plain share-page URL doesn't parse.
        XCTAssertNil(BattleDeepLink(pastedText: "https://battle.example.com/b/abc123"))
    }
}

// MARK: Roster → primitive failures never touch the network

private struct BattleStoreStubProvider: PokeProviding {
    var stats: BaseStats?
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func baseStats(speciesID: Int) async throws -> BaseStats {
        guard let stats else { throw URLError(.notConnectedToInternet) }
        return stats
    }
}

@MainActor
final class BattleStoreRosterTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let pikachuStats = BaseStats(hp: 35, attack: 55, defense: 40, specialAttack: 50, specialDefense: 50, speed: 90,
                                         abilities: [PokemonAbility(name: "static", isHidden: false)])

    private func mon(knownMoves: [Int] = []) -> MonState {
        MonState(baseID: 25, pathIDs: [25], plannedPathIDs: [25], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1, nature: .adamant, ability: "static", knownMoves: knownMoves)
    }

    private func stores(stats: BaseStats?) -> (battle: BattleStore, companion: CompanionStore) {
        let companionURL = FileManager.default.temporaryDirectory.appendingPathComponent("battle-\(UUID().uuidString).json")
        let companion = CompanionStore(provider: BattleStoreStubProvider(stats: stats), clock: { self.fixedNow }, fileURL: companionURL, rng: SeededRNG(seed: 7))
        let online = OnlineStore(defaults: UserDefaults(suiteName: "BattleStoreRosterTests.\(UUID().uuidString)")!)
        online.serverURL = "https://mock.test"
        return (BattleStore(companion: companion, online: online), companion)
    }

    /// A mon with no known moves yet (fresh hatch, pre auto-fill) can't field a legal roster slot —
    /// this must be caught before ever making a request, not surfaced as a confusing 400 from the server.
    func testCreateBattleFailsWithoutTouchingTheNetworkWhenAMonHasNoKnownMoves() async {
        let (battle, _) = stores(stats: pikachuStats)
        await battle.createBattle(roster: [mon(knownMoves: [])])
        XCTAssertEqual(battle.phase, .failed(.primitive(.noKnownMoves)))
    }

    func testCreateBattleFailsWhenBaseStatsAreUnavailable() async {
        let (battle, _) = stores(stats: nil)
        await battle.createBattle(roster: [mon(knownMoves: [84])])
        XCTAssertEqual(battle.phase, .failed(.primitive(.missingBaseStats)))
    }
}

// MARK: Network failure handling — same StubURLProtocol pattern as TradeTests.swift

private final class FixedStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Returns one queued (status, body) response per request, in order — for scripting a whole
/// create→poll→poll→choose exchange in one test, unlike `FixedStubURLProtocol`'s single fixed reply.
private final class QueuedStubURLProtocol: URLProtocol {
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
final class BattleStoreNetworkTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let pikachuStats = BaseStats(hp: 35, attack: 55, defense: 40, specialAttack: 50, specialDefense: 50, speed: 90,
                                         abilities: [PokemonAbility(name: "static", isHidden: false)])

    private func waitUntil(timeout: TimeInterval = 4, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private struct ReadyProvider: PokeProviding {
        let stats: BaseStats
        let moves: [Int: Move]
        func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
        func baseStats(speciesID: Int) async throws -> BaseStats { stats }
        func moveDetail(id: Int) async throws -> Move { moves[id]! }
    }

    private func mon() -> MonState {
        MonState(baseID: 25, pathIDs: [25], plannedPathIDs: [25], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1, nature: .adamant, ability: "static", knownMoves: [84])
    }

    private func makeStore(protocolClass: URLProtocol.Type, pollIntervalNanoseconds: UInt64 = 2_000_000_000) -> BattleStore {
        let companionURL = FileManager.default.temporaryDirectory.appendingPathComponent("battle-net-\(UUID().uuidString).json")
        let provider = ReadyProvider(stats: pikachuStats, moves: [84: Move(id: 84, name: "thunder-shock", type: .electric, power: 40, accuracy: 100, pp: 30, damageClass: .special, names: [:])])
        let companion = CompanionStore(provider: provider, clock: { self.fixedNow }, fileURL: companionURL, rng: SeededRNG(seed: 7))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolClass]
        let session = URLSession(configuration: config)
        let online = OnlineStore(defaults: UserDefaults(suiteName: "BattleStoreNetworkTests.\(UUID().uuidString)")!, session: session)
        online.serverURL = "https://mock.test"
        return BattleStore(companion: companion, online: online, session: session, pollIntervalNanoseconds: pollIntervalNanoseconds)
    }

    /// [Mirrors TradeStoreFailureTests] A 401 must not be a dead end — self-heals back to idle.
    func testCreateBattleSurfacesAuthErrorAndAutoReturnsToIdle() async {
        FixedStubURLProtocol.statusCode = 401
        FixedStubURLProtocol.body = Data(#"{"error":"Protected deployment"}"#.utf8)
        let battle = makeStore(protocolClass: FixedStubURLProtocol.self)

        await battle.createBattle(roster: [mon()])

        guard case .failed(.client(.server(status: 401))) = battle.phase else {
            return XCTFail("expected a 401 server error, got \(battle.phase)")
        }
        let returnedToIdle = await waitUntil { battle.phase == .idle }
        XCTAssertTrue(returnedToIdle, "a failed battle must not be a dead end requiring a manual tap")
    }

    func testJoinBattleWith404SurfacesExpired() async {
        FixedStubURLProtocol.statusCode = 404
        FixedStubURLProtocol.body = Data(#"{"error":"not found"}"#.utf8)
        let battle = makeStore(protocolClass: FixedStubURLProtocol.self)

        await battle.joinBattle(sessionId: "gone", server: "https://mock.test", roster: [mon()])

        XCTAssertEqual(battle.phase, .expired)
    }

    /// Scripts create → first poll ("waiting") → second poll ("active") — the phase should track
    /// the server's own status without the test needing to touch BattleStore's internals.
    func testCreateThenPollingTransitionsFromWaitingToBattling() async {
        QueuedStubURLProtocol.responses = [
            (200, Data(#"{"sessionId":"sess-1"}"#.utf8)),
            (200, Data(#"{"status":"waiting","turn":0}"#.utf8)),
            (200, Data("""
            {"status":"active","turn":1,"pendingChoice":"move",
             "you":{"displayName":"Ash","roster":[{"speciesID":25,"name":"Ash-0","fainted":false,"hpFraction":1}],"activeIndex":0},
             "opponent":{"displayName":"Gary","active":{"speciesID":4,"name":"Gary-0","fainted":false,"hpFraction":1},"rosterSize":1},
             "log":[]}
            """.utf8)),
        ]
        // Fast polling — real 2s ticks would make this test slow for no benefit.
        let battle = makeStore(protocolClass: QueuedStubURLProtocol.self, pollIntervalNanoseconds: 10_000_000)

        await battle.createBattle(roster: [mon()])
        guard case .waitingForOpponent(let sessionId, _) = battle.phase else {
            return XCTFail("expected waitingForOpponent right after create, got \(battle.phase)")
        }
        XCTAssertEqual(sessionId, "sess-1")

        let becameActive = await waitUntil {
            if case .battling(_, let view) = battle.phase { return view.status == "active" }
            return false
        }
        XCTAssertTrue(becameActive, "should transition to battling once the opponent joins and the sim starts")
    }
}
