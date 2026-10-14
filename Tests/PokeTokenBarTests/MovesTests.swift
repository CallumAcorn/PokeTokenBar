import XCTest
@testable import PokeTokenBar

// MARK: Learning moves (level-up/TM) + TM shop + move reroll

private struct MoveTestProvider: PokeProviding {
    let learnset: [LearnableMove]
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func learnableMoves(speciesID: Int) async throws -> [LearnableMove] { learnset }
}

/// Polls to wait for an async side effect fired via Task — same pattern as the identically-named
/// helper in CompanionTests.swift (that one is file-scope private, so it can't be reused; duplicated as-is).
@MainActor
private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

@MainActor
final class MovesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let monID = "moves-mon-1"
    private static let defaultUsedAtStage = 400_000_000

    /// Loads a state file with a fixed active mon (common/single-form) + known moves/TM stock/move
    /// reroll stock as specified. learnset is used by useMoveReroll and auto-learn (the
    /// applyUsage/update hooks) via the provider — the manual learn/teach functions take learnset as
    /// a direct parameter, so they're independent of the provider's value.
    private func store(knownMoves: [Int] = [], ownedTMs: [Int: Int] = [:], moveRerollCount: Int = 0,
                       used: Int = 1_000_000_000, usedAtStage: Int = defaultUsedAtStage,
                       learnset: [LearnableMove] = [], movesFeatureSeeded: Bool = false,
                       seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moves-\(UUID().uuidString).json")
        let movesJSON = "[" + knownMoves.map(String.init).joined(separator: ",") + "]"
        let party = "[{\"id\":\"\(monID)\",\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":\(usedAtStage),"
            + "\"rarity\":\"common\",\"totalForms\":1,\"isShiny\":false,\"knownMoves\":\(movesJSON)}]"
        let tmsJSON = "{" + ownedTMs.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",") + "}"
        let inv = moveRerollCount > 0 ? ",\"inventory\":{\"moveReroll\":\(moveRerollCount)}" : ""
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"party\":\(party),\"trainingSlotID\":\"\(monID)\",\"dex\":[],\"collectedFinals\":[],"
            + "\"ownedTMs\":\(tmsJSON),\"movesFeatureSeeded\":\(movesFeatureSeeded)\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: MoveTestProvider(learnset: learnset), clock: { self.now },
                              fileURL: url, rng: SeededRNG(seed: seed))
    }

    // MARK: Learnset parsing (PokeAPIClient.parseLearnableMoves)

    /// Real PokéAPI data quirk (found live on Charizard): an evolved species' Ember shows up twice
    /// within the same version group — level 1 (an evolution-inheritance artifact) and level 7 (the
    /// real, canonical level every reference lists). Left undeduped this double-rendered the row
    /// (ForEach id collision on moveID), let auto-learn append the same move to knownMoves twice,
    /// and — since the artifact is always the *lower* level — made the move look learnable from
    /// level 1, defeating the level gate for the whole learnset if kept.
    func testParseLearnableMovesDedupesDuplicateVersionGroupEntries() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "ember", url: "https://pokeapi.co/api/v2/move/52/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 7, move_learn_method: NamedRef(name: "level-up", url: nil),
                                      version_group: NamedRef(name: MoveDataVersion.versionGroup, url: nil)),
                VersionGroupDetailDTO(level_learned_at: 1, move_learn_method: NamedRef(name: "level-up", url: nil),
                                      version_group: NamedRef(name: MoveDataVersion.versionGroup, url: nil)),
            ])
        let out = PokeAPIClient.parseLearnableMoves(from: [entry])
        XCTAssertEqual(out.count, 1, "duplicate (move, method) entries in the same version group must collapse to one")
        XCTAssertEqual(out.first?.level, 7, "keeps the higher (canonical) of the two levels, not the evolution-artifact level 1")
    }

    /// Level-up and machine are tracked separately even for the same move — a move can be both
    /// TM-teachable and level-up learnable without one clobbering the other.
    func testParseLearnableMovesKeepsLevelUpAndMachineSeparate() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "flamethrower", url: "https://pokeapi.co/api/v2/move/53/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 47, move_learn_method: NamedRef(name: "level-up", url: nil),
                                      version_group: NamedRef(name: MoveDataVersion.versionGroup, url: nil)),
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "machine", url: nil),
                                      version_group: NamedRef(name: MoveDataVersion.versionGroup, url: nil)),
            ])
        let out = PokeAPIClient.parseLearnableMoves(from: [entry])
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.contains { $0.method == .levelUp && $0.level == 47 })
        XCTAssertTrue(out.contains { $0.method == .machine })
    }

    /// A different version group (or egg/tutor method) never leaks into the pinned learnset.
    func testParseLearnableMovesIgnoresOtherVersionGroupsAndMethods() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "irrelevant", url: "https://pokeapi.co/api/v2/move/1/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 5, move_learn_method: NamedRef(name: "level-up", url: nil),
                                      version_group: NamedRef(name: "sword-shield", url: nil)),
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "tutor", url: nil),
                                      version_group: NamedRef(name: "sword-shield", url: nil)),
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "egg", url: nil),
                                      version_group: NamedRef(name: "black-2-white-2", url: nil)),
            ])
        XCTAssertEqual(PokeAPIClient.parseLearnableMoves(from: [entry]), [])
    }

    /// Gen 5's tutors live in Black 2/White 2 — a tutor entry there counts, once, even if Black/White
    /// lists it too.
    func testParseLearnableMovesKeepsGen5TutorMoves() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "superpower", url: "https://pokeapi.co/api/v2/move/276/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "tutor", url: nil),
                                      version_group: NamedRef(name: "black-2-white-2", url: nil)),
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "tutor", url: nil),
                                      version_group: NamedRef(name: "black-white", url: nil)),
            ])
        XCTAssertEqual(PokeAPIClient.parseLearnableMoves(from: [entry]),
                       [LearnableMove(moveID: 276, method: .tutor, level: 0)])
    }

    /// Every mon hatches from an egg, so BW egg moves are kept (`LearnMethod.egg`).
    func testParseLearnableMovesKeepsEggMoves() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "rock-blast", url: "https://pokeapi.co/api/v2/move/350/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "egg", url: nil),
                                      version_group: NamedRef(name: MoveDataVersion.versionGroup, url: nil)),
            ])
        XCTAssertEqual(PokeAPIClient.parseLearnableMoves(from: [entry]),
                       [LearnableMove(moveID: 350, method: .egg, level: 0)])
    }

    /// A move from a Gen 3–4 game the species can't learn in Gen 5 is kept as `.legacy` (Blissey's
    /// Seismic Toss, an Emerald/FireRed tutor move). Gen 1–2 never count — nothing transfers from them.
    func testParseLearnableMovesKeepsGen3And4Moves() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "seismic-toss", url: "https://pokeapi.co/api/v2/move/69/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "tutor", url: nil),
                                      version_group: NamedRef(name: "emerald", url: nil)),
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "machine", url: nil),
                                      version_group: NamedRef(name: "heartgold-soulsilver", url: nil)),
            ])
        let gen2 = MoveEntryDTO(
            move: NamedRef(name: "mimic", url: "https://pokeapi.co/api/v2/move/102/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "machine", url: nil),
                                      version_group: NamedRef(name: "gold-silver", url: nil)),
            ])
        XCTAssertEqual(PokeAPIClient.parseLearnableMoves(from: [entry, gen2]),
                       [LearnableMove(moveID: 69, method: .legacy, level: 0)])
    }

    /// A move the species also learns in Gen 5 is listed under the Gen 5 method only.
    func testParseLearnableMovesDropsLegacyWhenGen5HasIt() {
        let entry = MoveEntryDTO(
            move: NamedRef(name: "thunderbolt", url: "https://pokeapi.co/api/v2/move/85/"),
            version_group_details: [
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "machine", url: nil),
                                      version_group: NamedRef(name: "platinum", url: nil)),
                VersionGroupDetailDTO(level_learned_at: 0, move_learn_method: NamedRef(name: "machine", url: nil),
                                      version_group: NamedRef(name: MoveDataVersion.versionGroup, url: nil)),
            ])
        XCTAssertEqual(PokeAPIClient.parseLearnableMoves(from: [entry]),
                       [LearnableMove(moveID: 85, method: .machine, level: 0)])
    }

    // MARK: Learning via level-up

    func testLearnLevelUpMoveWhenLevelReached() {
        let s = store()
        let level = s.trainingMon!.level
        let learnset = [LearnableMove(moveID: 100, method: .levelUp, level: level)]
        XCTAssertTrue(s.canLearnLevelUpMove(100, for: monID, learnset: learnset))
        XCTAssertTrue(s.learnLevelUpMove(100, for: monID, learnset: learnset))
        XCTAssertEqual(s.trainingMon?.knownMoves, [100])
    }

    func testCannotLearnLevelUpMoveAboveCurrentLevel() {
        let s = store()
        let level = s.trainingMon!.level
        let learnset = [LearnableMove(moveID: 100, method: .levelUp, level: level + 1)]
        XCTAssertFalse(s.canLearnLevelUpMove(100, for: monID, learnset: learnset))
        XCTAssertFalse(s.learnLevelUpMove(100, for: monID, learnset: learnset))
        XCTAssertEqual(s.trainingMon?.knownMoves, [])
    }

    // MARK: Teaching a TM

    func testTeachTMConsumesInventoryAndAddsMove() {
        let s = store(ownedTMs: [200: 1])
        let learnset = [LearnableMove(moveID: 200, method: .machine, level: 0)]
        XCTAssertTrue(s.canTeachTM(200, to: monID, learnset: learnset))
        XCTAssertTrue(s.teachTM(200, to: monID, learnset: learnset))
        XCTAssertEqual(s.trainingMon?.knownMoves, [200])
        XCTAssertEqual(s.tmCount(200), 0, "consumes 1 from stock")
    }

    func testCannotTeachTMWithoutStock() {
        let s = store()
        let learnset = [LearnableMove(moveID: 200, method: .machine, level: 0)]
        XCTAssertFalse(s.canTeachTM(200, to: monID, learnset: learnset))
        XCTAssertFalse(s.teachTM(200, to: monID, learnset: learnset))
    }

    func testCannotTeachMoveSpeciesCannotLearn() {
        let s = store(ownedTMs: [200: 1])
        XCTAssertFalse(s.canTeachTM(200, to: monID, learnset: []))
        XCTAssertFalse(s.teachTM(200, to: monID, learnset: []))
        XCTAssertEqual(s.tmCount(200), 1, "a failed attempt doesn't consume stock")
    }

    func testAlreadyKnownMoveCannotBeTaughtAgain() {
        let s = store(knownMoves: [200], ownedTMs: [200: 1])
        let learnset = [LearnableMove(moveID: 200, method: .machine, level: 0)]
        XCTAssertFalse(s.canTeachTM(200, to: monID, learnset: learnset))
    }

    /// Fails without a slot once the moveset is already full 4; with a slot, only that slot gets replaced.
    func testTeachTMRequiresSlotWhenMovesetFull() {
        let s = store(knownMoves: [1, 2, 3, 4], ownedTMs: [200: 1])
        let learnset = [LearnableMove(moveID: 200, method: .machine, level: 0)]
        XCTAssertFalse(s.teachTM(200, to: monID, learnset: learnset), "fails without a slot")
        XCTAssertEqual(s.tmCount(200), 1, "the failed attempt leaves stock unchanged")
        XCTAssertTrue(s.teachTM(200, to: monID, learnset: learnset, replacingSlot: 2))
        XCTAssertEqual(s.trainingMon?.knownMoves, [1, 2, 200, 4])
        XCTAssertEqual(s.tmCount(200), 0)
    }

    // MARK: TM shop

    func testTMShopPriceAndBuy() {
        let s = store(used: TM.price)
        XCTAssertTrue(s.canBuyTM(101))
        XCTAssertTrue(s.buyTM(101))
        XCTAssertEqual(s.tmCount(101), 1)
        XCTAssertEqual(s.state.spentTokens, TM.price)
    }

    func testCannotBuyTMBelowPrice() {
        let s = store(used: TM.price - 1)
        XCTAssertFalse(s.canBuyTM(101))
        XCTAssertFalse(s.buyTM(101))
    }

    // MARK: Egg moves — every mon hatched from an egg, so they're free at any level

    func testEggMoveLearnableAtAnyLevel() {
        let s = store()
        let learnset = [LearnableMove(moveID: 300, method: .egg, level: 0)]
        XCTAssertTrue(s.canLearnLevelUpMove(300, for: monID, learnset: learnset))
        XCTAssertTrue(s.learnLevelUpMove(300, for: monID, learnset: learnset))
        XCTAssertEqual(s.trainingMon?.knownMoves, [300])
        XCTAssertFalse(s.canLearnLevelUpMove(300, for: monID, learnset: learnset), "already known")
    }

    func testTutorMoveLearnableAtAnyLevel() {
        let s = store()
        let learnset = [LearnableMove(moveID: 276, method: .tutor, level: 0)]
        XCTAssertTrue(s.learnLevelUpMove(276, for: monID, learnset: learnset))
        XCTAssertEqual(s.trainingMon?.knownMoves, [276])
    }

    func testUseMoveRerollIncludesEggMoves() async {
        let learnset = [LearnableMove(moveID: 20, method: .egg, level: 0)]
        let s = store(knownMoves: [999], moveRerollCount: 1, learnset: learnset)
        let ok = await s.useMoveReroll()
        XCTAssertTrue(ok)
        XCTAssertEqual(s.trainingMon?.knownMoves, [20])
    }

    // MARK: Move reroll

    func testUseMoveRerollDrawsOnlyFromEligiblePool() async {
        let level = PokemonBalance.level(rarity: .common, totalForms: 1, stageIndex: 0,
                                         usedAtStage: Self.defaultUsedAtStage)
        let learnset = [
            LearnableMove(moveID: 10, method: .levelUp, level: level),
            LearnableMove(moveID: 11, method: .levelUp, level: level + 50),   // not learnable yet — excluded from the pool
            LearnableMove(moveID: 12, method: .machine, level: 0),
        ]
        let s = store(knownMoves: [999], moveRerollCount: 1, learnset: learnset)
        let ok = await s.useMoveReroll()
        XCTAssertTrue(ok)
        let known = Set(s.trainingMon?.knownMoves ?? [])
        XCTAssertEqual(known, [10, 12], "11 doesn't meet the level requirement, so it's excluded from the pool")
        XCTAssertEqual(s.itemCount(.moveReroll), 0, "consumes 1 from stock")
    }

    func testMoveRerollFailsWithoutStock() async {
        let s = store(knownMoves: [999], moveRerollCount: 0,
                      learnset: [LearnableMove(moveID: 10, method: .machine, level: 0)])
        XCTAssertFalse(s.canUseMoveReroll)
        let ok = await s.useMoveReroll()
        XCTAssertFalse(ok)
        XCTAssertEqual(s.trainingMon?.knownMoves, [999], "a failed attempt leaves the existing moveset untouched")
    }

    func testMoveRerollFailsWithEmptyPool() async {
        let s = store(knownMoves: [999], moveRerollCount: 1, learnset: [])
        let ok = await s.useMoveReroll()
        XCTAssertFalse(ok)
        XCTAssertEqual(s.itemCount(.moveReroll), 1, "an empty candidate pool doesn't consume stock")
    }

    // MARK: Auto-learn — fills slots with no player involvement until all 4 are full.

    func testApplyUsageAutoLearnsUpToFourLevelUpMoves() async {
        let learnset = (1...6).map { LearnableMove(moveID: $0, method: .levelUp, level: $0) }
        let s = store(learnset: learnset)
        s.applyUsage(0)   // delta 0 still fires the auto-learn hook, since the (species,level) dedup key is new
        let filled = await waitUntil { s.trainingMon?.knownMoves.count == 4 }
        XCTAssertTrue(filled, "should auto-fill up to 4")
        XCTAssertEqual(s.trainingMon?.knownMoves, [1, 2, 3, 4], "only the 4 lowest-level ones — the remaining 2 wait for a manual replace")
    }

    func testAutoLearnFillsRemainingSlotsWithoutTouchingExisting() async {
        let learnset = [LearnableMove(moveID: 1, method: .levelUp, level: 1),
                        LearnableMove(moveID: 2, method: .levelUp, level: 2)]
        let s = store(knownMoves: [999], learnset: learnset)   // 999 = an existing known move not in the learnset
        s.applyUsage(0)
        let filled = await waitUntil { s.trainingMon?.knownMoves.count == 3 }
        XCTAssertTrue(filled)
        XCTAssertEqual(s.trainingMon?.knownMoves, [999, 1, 2], "the existing slot stays, only the open ones fill, lowest level first")
    }

    func testAutoLearnLeavesFullMovesetUntouched() async {
        let learnset = [LearnableMove(moveID: 5, method: .levelUp, level: 1)]
        let s = store(knownMoves: [1, 2, 3, 4], learnset: learnset)
        s.applyUsage(0)
        try? await Task.sleep(nanoseconds: 50_000_000)   // give the Task a chance to run
        XCTAssertEqual(s.trainingMon?.knownMoves, [1, 2, 3, 4], "once 4 are full, auto-learn stops touching it — manual replace takes over")
    }

    // MARK: Save migration — fills the party of a pre-feature save once.

    func testUpdateMigratesExistingSaveMovesOnce() async {
        let learnset = (1...5).map { LearnableMove(moveID: $0, method: .levelUp, level: $0) }
        let s = store(learnset: learnset)   // movesFeatureSeeded defaults to false, knownMoves starts empty
        XCTAssertFalse(s.state.movesFeatureSeeded)
        s.update(todayTokensByProvider: [:], todayDate: "d", monthTotal: 0, burnTier: .idle,
                limitWarning: false, hasUsageData: false)
        let seeded = await waitUntil { s.state.movesFeatureSeeded }
        XCTAssertTrue(seeded, "the flag should be set once migration completes")
        XCTAssertEqual(s.trainingMon?.knownMoves, [1, 2, 3, 4], "fills only the first 4 (lowest level first)")
    }

    func testUpdateSkipsMigrationWhenAlreadySeeded() async {
        let learnset = [LearnableMove(moveID: 1, method: .levelUp, level: 1)]
        let s = store(learnset: learnset, movesFeatureSeeded: true)
        s.update(todayTokensByProvider: [:], todayDate: "d", monthTotal: 0, burnTier: .idle,
                limitWarning: false, hasUsageData: false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(s.trainingMon?.knownMoves, [], "an already-seeded save doesn't get refilled")
    }
}

/// Per-species learnsets, for the path-aware learnset (egg moves live on a line's first stage).
private struct PathLearnsetProvider: PokeProviding {
    let bySpecies: [Int: [LearnableMove]]
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func learnableMoves(speciesID: Int) async throws -> [LearnableMove] { bySpecies[speciesID] ?? [] }
}

@MainActor
final class EggMoveLearnsetTests: XCTestCase {
    private func store(_ bySpecies: [Int: [LearnableMove]]) -> CompanionStore {
        CompanionStore(provider: PathLearnsetProvider(bySpecies: bySpecies),
                       fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("egg-\(UUID()).json"))
    }

    /// Shellder (90) → Cloyster (91): PokéAPI lists Rock Blast (egg) and Shell Smash (level-up) on
    /// Shellder only. A Cloyster gets both, at Shellder's level requirement; Shellder's TMs don't come
    /// along (TMs stay per species).
    func testEarlierStageMovesComeAlongButNotTheirTMs() async {
        let s = store([
            90: [LearnableMove(moveID: 350, method: .egg, level: 0),
                 LearnableMove(moveID: 504, method: .levelUp, level: 56),
                 LearnableMove(moveID: 276, method: .tutor, level: 0),
                 LearnableMove(moveID: 999, method: .machine, level: 0)],
            91: [LearnableMove(moveID: 556, method: .levelUp, level: 52), LearnableMove(moveID: 58, method: .machine, level: 0)],
        ])
        let learnset = await s.learnableMoves(speciesID: 91, pathIDs: [90, 91])
        XCTAssertEqual(Set(learnset.map(\.moveID)), [556, 58, 350, 504, 276])
        XCTAssertEqual(learnset.first { $0.moveID == 504 }, LearnableMove(moveID: 504, method: .levelUp, level: 56))
    }

    /// A level-up move both stages list keeps the lower level — it was reachable before evolving.
    func testSameLevelUpMoveKeepsTheLowestLevel() async {
        let s = store([
            90: [LearnableMove(moveID: 62, method: .levelUp, level: 20)],
            91: [LearnableMove(moveID: 62, method: .levelUp, level: 1)],
            92: [LearnableMove(moveID: 62, method: .levelUp, level: 40)],
        ])
        let fromLater = await s.learnableMoves(speciesID: 91, pathIDs: [90, 91])
        XCTAssertEqual(fromLater, [LearnableMove(moveID: 62, method: .levelUp, level: 1)])
        let fromEarlier = await s.learnableMoves(speciesID: 92, pathIDs: [90, 92])
        XCTAssertEqual(fromEarlier, [LearnableMove(moveID: 62, method: .levelUp, level: 20)])
    }

    /// The same egg move listed on two stages appears once.
    func testEggMovesAreNotDuplicated() async {
        let egg = LearnableMove(moveID: 350, method: .egg, level: 0)
        let s = store([90: [egg], 91: [egg]])
        let learnset = await s.learnableMoves(speciesID: 91, pathIDs: [90, 91])
        XCTAssertEqual(learnset, [egg])
    }

    /// An earlier stage's older-game move is free on the evolved mon, unless the evolved mon learns it
    /// in Gen 5 — then only the Gen 5 entry shows.
    func testLegacyMovesFollowThePathAndYieldToGen5() async {
        let s = store([
            113: [LearnableMove(moveID: 69, method: .legacy, level: 0), LearnableMove(moveID: 85, method: .legacy, level: 0)],
            242: [LearnableMove(moveID: 85, method: .machine, level: 0)],
        ])
        let learnset = await s.learnableMoves(speciesID: 242, pathIDs: [113, 242])
        XCTAssertEqual(Set(learnset.map { "\($0.moveID)-\($0.method.rawValue)" }), ["69-legacy", "85-machine"])
    }

    /// Only stages actually reached count — a planned future evolution's egg moves don't.
    func testReachedPathStopsAtTheCurrentStage() {
        let mon = MonState(baseID: 90, pathIDs: [90, 91], plannedPathIDs: [90, 91], stageIndex: 0,
                           usedAtStage: 0, rarity: .common, totalForms: 2)
        XCTAssertEqual(mon.reachedPathIDs, [90])
        var evolved = mon
        evolved.stageIndex = 1
        XCTAssertEqual(evolved.reachedPathIDs, [90, 91])
    }
}
