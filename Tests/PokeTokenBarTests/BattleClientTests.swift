import XCTest
@testable import PokeTokenBar

// MARK: Wire-format decoding — literal fixtures captured from a real PokeTokenBarOnline response,
// not hand-guessed JSON, so a server-side field rename would actually be caught here.

final class BattleClientDecodingTests: XCTestCase {
    func testDecodesWaitingStatusWithNoOptionalFields() throws {
        let json = Data(#"{"status":"waiting","turn":0}"#.utf8)
        let view = try JSONDecoder().decode(BattleClient.BattleView.self, from: json)
        XCTAssertEqual(view.status, "waiting")
        XCTAssertEqual(view.turn, 0)
        XCTAssertNil(view.you)
        XCTAssertNil(view.opponent)
        XCTAssertNil(view.log)
        XCTAssertNil(view.result)
    }

    /// Captured verbatim from a real create→join→choose exchange against the live server.
    func testDecodesActiveBattleAfterATurn() throws {
        let json = Data("""
        {"status":"active","turn":2,"pendingChoice":"move",
         "you":{"displayName":"Ash","roster":[{"speciesID":1,"name":"Ash-0","fainted":false,"hpFraction":0.8}],"activeIndex":0},
         "opponent":{"displayName":"Gary","active":{"speciesID":4,"name":"Gary-0","fainted":false,"hpFraction":0.7586206896551724},"rosterSize":1},
         "log":["|turn|1","|move|p2a: Gary-0|Scratch|p1a: Ash-0"]}
        """.utf8)
        let view = try JSONDecoder().decode(BattleClient.BattleView.self, from: json)
        XCTAssertEqual(view.pendingChoice, "move")
        XCTAssertEqual(view.you?.roster.first?.speciesID, 1)
        XCTAssertEqual(view.you?.activeIndex, 0)
        XCTAssertEqual(try XCTUnwrap(view.opponent?.active?.hpFraction), 0.7586206896551724, accuracy: 1e-9)
        XCTAssertEqual(view.opponent?.rosterSize, 1)
        XCTAssertEqual(view.log?.count, 2)
        XCTAssertNil(view.result, "not decided yet")
    }

    func testDecodesCompletedBattleWithResult() throws {
        let json = Data("""
        {"status":"completed","turn":2,"pendingChoice":"","result":"loss",
         "you":{"displayName":"Ash","roster":[],"activeIndex":0},
         "opponent":{"displayName":"Gary","active":null,"rosterSize":1},"log":[]}
        """.utf8)
        let view = try JSONDecoder().decode(BattleClient.BattleView.self, from: json)
        XCTAssertEqual(view.status, "completed")
        XCTAssertEqual(view.result, "loss")
        XCTAssertNil(view.opponent?.active, "a fully-fainted-out opponent side can report no active mon")
    }

    /// `createdAt` is a raw `Date.now()` off the server — a plain number, not an ISO 8601 string like
    /// a trade payload's embedded dates. Decoding this as `Date` (or via a `.iso8601` strategy) would
    /// fail outright; locking in that it's a plain `Double` instead.
    func testDecodesOpenBattleCreatedAtAsRawEpochMillis() throws {
        let json = Data(#"{"battles":[{"sessionId":"abc","displayName":"Ash","rosterSize":2,"createdAt":1787665470123}]}"#.utf8)
        struct Wrapper: Decodable { let battles: [BattleClient.OpenBattle] }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(decoded.battles.first?.createdAt, 1787665470123)
    }
}

// MARK: Primitive encoding — field names must match pkmnAdapter.ts's isMonPrimitive exactly

final class BattleClientPrimitiveEncodingTests: XCTestCase {
    func testEncodesWithServerExpectedKeyNames() throws {
        let primitive = BattleClient.Primitive(
            speciesID: 25, level: 10, nature: "hardy", ability: "static",
            ivs: .init(hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31),
            evs: .init(hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0),
            moves: ["thunder-shock"])
        let data = try JSONEncoder().encode(primitive)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["speciesID"] as? Int, 25)
        let ivs = try XCTUnwrap(obj["ivs"] as? [String: Any])
        XCTAssertEqual(ivs["hp"] as? Int, 31)
        XCTAssertEqual(ivs["atk"] as? Int, 31)
        XCTAssertNil(ivs["attack"], "must use the server's StatsTable key names, not StatSpread's")
    }
}

// MARK: MonState → Primitive derivation

private struct BattleStubProvider: PokeProviding {
    var stats: BaseStats?
    var moves: [Int: Move] = [:]

    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func baseStats(speciesID: Int) async throws -> BaseStats {
        guard let stats else { throw URLError(.notConnectedToInternet) }
        return stats
    }
    func moveDetail(id: Int) async throws -> Move {
        guard let move = moves[id] else { throw URLError(.notConnectedToInternet) }
        return move
    }
}

@MainActor
final class BattleClientPrimitiveDerivationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func mon(nature: PokemonNature? = .adamant, ability: String? = "static", knownMoves: [Int] = [84]) -> MonState {
        MonState(baseID: 25, pathIDs: [25], plannedPathIDs: [25], stageIndex: 0, usedAtStage: 0,
                 rarity: .common, totalForms: 1, nature: nature, ability: ability,
                 ivs: StatSpread(hp: 20, attack: 15, defense: 10, specialAttack: 25, specialDefense: 5, speed: 31),
                 evs: StatSpread(hp: 4, attack: 252, defense: 0, specialAttack: 0, specialDefense: 0, speed: 252),
                 knownMoves: knownMoves)
    }

    private func store(provider: BattleStubProvider) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("battle-client-\(UUID().uuidString).json")
        return CompanionStore(provider: provider, clock: { self.fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    private let pikachuStats = BaseStats(hp: 35, attack: 55, defense: 40, specialAttack: 50, specialDefense: 50, speed: 90,
                                         abilities: [PokemonAbility(name: "static", isHidden: false),
                                                     PokemonAbility(name: "lightning-rod", isHidden: true)])

    func testMapsSpeciesLevelIVsEVsAndMoveSlugs() async throws {
        let s = store(provider: BattleStubProvider(stats: pikachuStats, moves: [84: Move(id: 84, name: "thunder-shock", type: .electric, power: 40, accuracy: 100, pp: 30, damageClass: .special, names: [:])]))
        let primitive = try await BattleClient.primitive(for: mon(), companion: s)

        XCTAssertEqual(primitive.speciesID, 25)
        XCTAssertEqual(primitive.nature, "adamant")
        XCTAssertEqual(primitive.ability, "static")
        XCTAssertEqual(primitive.ivs, .init(hp: 20, atk: 15, def: 10, spa: 25, spd: 5, spe: 31))
        XCTAssertEqual(primitive.evs, .init(hp: 4, atk: 252, def: 0, spa: 0, spd: 0, spe: 252))
        XCTAssertEqual(primitive.moves, ["thunder-shock"])
    }

    func testFallsBackToNeutralNatureForALegacyMonWithNoNatureRoll() async throws {
        let s = store(provider: BattleStubProvider(stats: pikachuStats, moves: [84: Move(id: 84, name: "thunder-shock", type: .electric, power: 40, accuracy: 100, pp: 30, damageClass: .special, names: [:])]))
        let primitive = try await BattleClient.primitive(for: mon(nature: nil), companion: s)
        XCTAssertEqual(primitive.nature, "hardy", "hardy is neutral — same net effect StatCalc already gives a nil nature")
    }

    func testFallsBackToLegacyAbilityResolutionForALegacyMonWithNoAbilityRoll() async throws {
        let s = store(provider: BattleStubProvider(stats: pikachuStats, moves: [84: Move(id: 84, name: "thunder-shock", type: .electric, power: 40, accuracy: 100, pp: 30, damageClass: .special, names: [:])]))
        let primitive = try await BattleClient.primitive(for: mon(ability: nil), companion: s)
        // MonState.effectiveAbility deterministically resolves a legacy nil ability from the id —
        // just assert it's one of this species' real candidates, not that it picked a specific one.
        XCTAssertTrue(["static", "lightning-rod"].contains(primitive.ability))
    }

    func testThrowsForAMonWithNoKnownMovesYet() async {
        let s = store(provider: BattleStubProvider(stats: pikachuStats))
        do {
            _ = try await BattleClient.primitive(for: mon(knownMoves: []), companion: s)
            XCTFail("expected noKnownMoves")
        } catch BattleClient.PrimitiveError.noKnownMoves {
            // expected
        } catch {
            XCTFail("expected noKnownMoves, got \(error)")
        }
    }

    func testThrowsWhenBaseStatsAreUnavailable() async {
        let s = store(provider: BattleStubProvider(stats: nil))
        do {
            _ = try await BattleClient.primitive(for: mon(), companion: s)
            XCTFail("expected missingBaseStats")
        } catch BattleClient.PrimitiveError.missingBaseStats {
            // expected
        } catch {
            XCTFail("expected missingBaseStats, got \(error)")
        }
    }

    /// 두 상수의 순서가 계약이다. 종료 백스톱이 요청 데드라인보다 짧으면 요청이 스스로 끝나기 전에
    /// 앱이 죽어 leave 가 매번 잘리고 서버에 stale 세션이 남는다. 반대로 요청이 백스톱보다 길면
    /// 종료가 그만큼 늘어진다. 어느 쪽 상수를 나중에 손대도 이 테스트가 먼저 걸린다.
    @MainActor
    func testQuitDeadlineOutlivesTheRequestTimeout() {
        XCTAssertGreaterThan(AppDelegate.quitLeaveDeadline, BattleClient.requestTimeout,
                             "종료 백스톱은 요청 데드라인보다 길어야 한다")
    }

    /// 요청에 데드라인이 실제로 박히는가. URLRequest 기본값 60s 를 그대로 두면 종료 경로가 그만큼
    /// 매달린다 — 이 PR 이 처음 들어왔을 때가 그 상태였다.
    func testRequestsCarryAnExplicitTimeout() {
        XCTAssertLessThan(BattleClient.requestTimeout, 60, "URLRequest 기본값을 그대로 쓰고 있다")
        XCTAssertGreaterThan(BattleClient.requestTimeout, 0)
    }
}
