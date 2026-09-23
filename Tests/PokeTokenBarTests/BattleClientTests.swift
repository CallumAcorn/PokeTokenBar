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

    // MARK: Spectator wire format — see spectator.md

    func testDecodesSpectatorViewWithBothSidesRestricted() throws {
        let json = Data("""
        {"status":"active","turn":2,
         "p1":{"displayName":"Ash","active":{"speciesID":1,"name":"Ash-0","fainted":false,"hpFraction":0.8},"rosterSize":1},
         "p2":{"displayName":"Gary","active":{"speciesID":4,"name":"Gary-0","fainted":false,"hpFraction":0.75},"rosterSize":1},
         "hostLeadSpeciesID":1,"log":["|turn|1"]}
        """.utf8)
        let view = try JSONDecoder().decode(BattleClient.SpectatorView.self, from: json)
        XCTAssertEqual(view.p1?.displayName, "Ash")
        XCTAssertEqual(view.p2?.active?.speciesID, 4)
        XCTAssertNil(view.winner, "not decided yet")
    }

    func testDecodesSpectatorViewWinnerAsPSideNotWinLoss() throws {
        let json = Data(#"{"status":"completed","turn":3,"winner":"p2"}"#.utf8)
        let view = try JSONDecoder().decode(BattleClient.SpectatorView.self, from: json)
        XCTAssertEqual(view.winner, "p2")
    }

    func testDecodesLiveBattleListing() throws {
        let json = Data(#"{"battles":[{"sessionId":"abc","p1DisplayName":"Ash","p2DisplayName":"Gary","turn":3,"createdAt":1787665470123}]}"#.utf8)
        struct Wrapper: Decodable { let battles: [BattleClient.LiveBattle] }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(decoded.battles.first?.p1DisplayName, "Ash")
        XCTAssertEqual(decoded.battles.first?.turn, 3)
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

    // MARK: opponentRosterNames — same "|poke|SIDE|Species, Level|" fixture shape BattleViewTests uses.

    func testOpponentRosterNamesReturnsTheOtherSidesFullRevealedRoster() {
        let log = [
            "|poke|p1|Pikachu, L50|",
            "|poke|p1|Charizard, L50|",
            "|poke|p2|Venusaur, L59|",
            "|poke|p2|Onix, L59|",
            "|teampreview",
            "|switch|p1a: Ash-0|Pikachu, L50, M|100/100",
            "|switch|p2a: Gary-0|Venusaur, L59, M|100/100",
        ]
        XCTAssertEqual(BattleClient.opponentRosterNames(log: log, myDisplayName: "Ash"), ["Venusaur", "Onix"])
        // Same log, opposite viewer — proves this is never hardcoded to p1/p2, only to whichever
        // ident nickname matches the caller's own display name.
        XCTAssertEqual(BattleClient.opponentRosterNames(log: log, myDisplayName: "Gary"), ["Pikachu", "Charizard"])
    }

    func testOpponentRosterNamesIsEmptyWithoutAnIdentToAnchorMySideOn() {
        let log = ["|poke|p1|Pikachu, L50|", "|poke|p2|Venusaur, L59|"]
        XCTAssertEqual(BattleClient.opponentRosterNames(log: log, myDisplayName: "Ash"), [])
    }

    /// `activeMoves` 는 서버가 주는 값이고, 서버는 초대 링크로 지정될 수 있어 신뢰 대상이 아니다.
    /// 소비 루프가 슬롯마다 `moveDetail(name:)` 을 한 번 호출하므로, 자르지 않으면 슬롯 수만큼
    /// PokéAPI 요청이 나간다(남의 서비스로 증폭되고, 순차 await 라 화면도 그동안 멈춘다).
    /// 4개 초과는 정상 대전에서 나올 수 없으므로 잘라도 잃는 정보가 없다.
    func testActiveMovesFromTheServerAreCappedAtTheMoveLimit() {
        let hostile = (0..<500).map {
            BattleClient.ActiveMoveSlot(moveSlug: "tackle-\($0)", pp: 1, maxPP: 1, disabled: false)
        }
        let capped = BattleClient.cappedActiveMoves(hostile)
        XCTAssertEqual(capped?.count, MonState.maxKnownMoves, "서버가 준 길이를 그대로 믿었다")
        XCTAssertEqual(capped?.first?.moveSlug, "tackle-0", "앞에서부터 잘라 순서를 보존해야 한다")
    }

    /// 정상 길이는 그대로 통과하고, nil(이 턴은 기술 선택이 아님)도 nil 로 남아야 한다.
    func testNormalActiveMovesPassThroughUnchanged() {
        let normal = (0..<3).map {
            BattleClient.ActiveMoveSlot(moveSlug: "m\($0)", pp: 5, maxPP: 5, disabled: false)
        }
        XCTAssertEqual(BattleClient.cappedActiveMoves(normal)?.count, 3)
        XCTAssertNil(BattleClient.cappedActiveMoves(nil))
    }

    /// 팀 프리뷰 로그는 서버가 주고, 뽑힌 이름마다 PokéAPI 요청이 한 번씩 나간다. 서버가 보낸 서로 다른
    /// 이름 수만큼 요청이 증폭되면 안 된다 — 실제 대전은 p1/p2 × 최대 6마리가 전부다.
    func testTeamPreviewIsCappedToTwoSidesOfSix() {
        var log: [String] = []
        for side in ["p1", "p2", "p3", "evil"] {
            for n in 0..<200 { log.append("|poke|\(side)|Species\(side)\(n), L50|") }
        }
        let names = BattleClient.teamPreviewSpeciesNames(log)
        XCTAssertEqual(Set(names.keys), ["p1", "p2"], "p1/p2 외의 진영 키가 통과했다")
        XCTAssertEqual(names.values.reduce(0) { $0 + $1.count }, 2 * BattleClient.maxRosterSize,
                       "서버가 준 이름 수만큼 PokéAPI 요청이 나갈 수 있었다")
    }

    /// 정상 팀 프리뷰는 그대로 — 순서와 종명 파싱(레벨 접미사 제거)이 보존돼야 한다.
    func testNormalTeamPreviewParsesUnchanged() {
        let log = ["|poke|p1|Pikachu, L50, F|", "|poke|p1|Mr. Mime, L48|", "|poke|p2|Ho-Oh, L60|"]
        let names = BattleClient.teamPreviewSpeciesNames(log)
        XCTAssertEqual(names["p1"], ["Pikachu", "Mr. Mime"])
        XCTAssertEqual(names["p2"], ["Ho-Oh"])
    }
}
