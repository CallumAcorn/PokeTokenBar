import XCTest
@testable import PokeTokenBar

// MARK: Day Care (doc: specs/2026-10-21-day-care.md)

/// Species table for the Day Care — egg groups, gender ratios, egg cycles, abilities and lines.
private final class DayCareProvider: PokeProviding, @unchecked Sendable {
    struct Species {
        let groups: [String]; let rate: Int; let hatch: Int?
        let abilities: [PokemonAbility]; let rarity: Rarity; let line: [Int]
    }
    static let table: [Int: Species] = [
        1: Species(groups: ["monster", "plant"], rate: 1, hatch: 20,
                   abilities: [.init(name: "overgrow", isHidden: false), .init(name: "chlorophyll", isHidden: true)],
                   rarity: .rare, line: [1, 2, 3]),
        4: Species(groups: ["monster", "dragon"], rate: 1, hatch: 20,
                   abilities: [.init(name: "blaze", isHidden: false), .init(name: "solar-power", isHidden: true)],
                   rarity: .rare, line: [4, 5, 6]),
        132: Species(groups: ["ditto"], rate: -1, hatch: 20,
                     abilities: [.init(name: "limber", isHidden: false)], rarity: .common, line: [132]),
        129: Species(groups: ["water2", "dragon"], rate: 4, hatch: 5,
                     abilities: [.init(name: "swift-swim", isHidden: false)], rarity: .common, line: [129, 130]),
        150: Species(groups: ["no-eggs"], rate: -1, hatch: 120,
                     abilities: [.init(name: "pressure", isHidden: false)], rarity: .legendary, line: [150]),
        29: Species(groups: ["monster", "field"], rate: 8, hatch: 20,
                    abilities: [.init(name: "poison-point", isHidden: false)], rarity: .common, line: [29, 30, 31]),
        32: Species(groups: ["monster", "field"], rate: 0, hatch: 20,
                    abilities: [.init(name: "poison-point", isHidden: false)], rarity: .common, line: [32, 33, 34]),
    ]
    private let lock = NSLock()
    private var lineFailures: Int
    init(lineFailures: Int = 0) { self.lineFailures = lineFailures }
    func failLines(_ n: Int) { lock.withLock { lineFailures = n } }

    /// Holds `baseStats` (mid drop-off) until `release()`, so a test can change state inside the await.
    private var held: CheckedContinuation<Void, Never>?
    private var holding = false
    func holdBaseStats() { lock.withLock { holding = true } }
    var isHeld: Bool { lock.withLock { held != nil } }
    func release() { lock.withLock { () -> CheckedContinuation<Void, Never>? in
        holding = false; defer { held = nil }; return held }?.resume() }

    private func species(_ id: Int) throws -> Species {
        guard let sp = Self.table[id] else { throw URLError(.fileDoesNotExist) }
        return sp
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let fail = lock.withLock { () -> Bool in
            guard lineFailures > 0 else { return false }
            lineFailures -= 1
            return true
        }
        if fail { throw URLError(.notConnectedToInternet) }
        let sp = try species(baseSpeciesID)
        var node = EvoNode(speciesID: sp.line.last!, children: [])
        for id in sp.line.dropLast().reversed() { node = EvoNode(speciesID: id, children: [node]) }
        return EvoLine(baseID: baseSpeciesID, tree: node, rarity: sp.rarity,
                       names: Dictionary(uniqueKeysWithValues: sp.line.map { ($0, ["en": "Species\($0)"]) }))
    }
    /// A random roll always picks Charmander — so a Day Care egg that loses its species shows up as #4.
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 4, captureRate: 45)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func eggInfo(speciesID: Int) async throws -> EggInfo {
        let sp = try species(speciesID)
        return EggInfo(eggGroups: sp.groups, genderRate: sp.rate, hatchCounter: sp.hatch)
    }
    func baseStats(speciesID: Int) async throws -> BaseStats {
        if lock.withLock({ holding }) {
            await withCheckedContinuation { c in lock.withLock { held = c } }
        }
        return BaseStats(hp: 45, attack: 49, defense: 49, specialAttack: 65, specialDefense: 65, speed: 45,
                  abilities: try species(speciesID).abilities)
    }
    func learnableMoves(speciesID: Int) async throws -> [LearnableMove] {
        speciesID == 1 ? [LearnableMove(moveID: 113, method: .egg, level: 0),
                          LearnableMove(moveID: 33, method: .levelUp, level: 1)] : []
    }
}

@MainActor
final class DayCareTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func mon(_ id: String, base: Int, gender: Gender?, ivs: Int = 10, nature: PokemonNature = .hardy,
                            ability: String? = nil, moves: [Int] = [], via: AcquisitionSource = .egg) -> MonState {
        let spread = StatSpread(hp: ivs, attack: ivs, defense: ivs, specialAttack: ivs, specialDefense: ivs, speed: ivs)
        return MonState(id: id, baseID: base, pathIDs: [base], stageIndex: 0, usedAtStage: 0, rarity: .common,
                        totalForms: 1, nature: nature, ability: ability, ivs: spread, acquiredVia: via,
                        knownMoves: moves, gender: gender)
    }

    /// Training Charmander, plus benched: female Bulbasaur with its hidden ability, a traded male
    /// Charmander, Ditto, Mewtwo, a male Magikarp, a second female Bulbasaur and a female Nidoran.
    private func store(tokens: Int = 10_000_000_000, inventory: [String: Int] = [:], training: Bool = true,
                       provider: DayCareProvider = DayCareProvider(), seed: UInt64 = 1,
                       edit: (inout CompanionState) -> Void = { _ in }) -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.usedSinceInstall = tokens
        st.lastDate = "d"
        st.language = .en
        st.party = [
            Self.mon("train", base: 4, gender: .male),
            Self.mon("bulbaF", base: 1, gender: .female, ivs: 31, nature: .adamant, ability: "chlorophyll", moves: [113, 33]),
            Self.mon("charM", base: 4, gender: .male, ivs: 0, nature: .timid, via: .trade(from: "Ash")),
            Self.mon("ditto", base: 132, gender: .genderless),
            Self.mon("mewtwo", base: 150, gender: .genderless),
            Self.mon("karpM", base: 129, gender: .male),
            Self.mon("bulbaF2", base: 1, gender: .female),
            Self.mon("nidoF", base: 29, gender: .female),
        ]
        st.trainingSlotID = training ? "train" : nil
        st.inventory = inventory
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daycare-\(UUID().uuidString).json")
        try? JSONEncoder().encode(st).write(to: url)
        return CompanionStore(provider: provider, clock: { self.now }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    private func use(_ s: CompanionStore, _ today: Int) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
    }

    private func mon(_ s: CompanionStore, _ id: String) -> MonState? { s.state.party.first { $0.id == id } }

    // MARK: Rules (pure)

    private func candidate(_ id: String, _ groups: [String], _ gender: Gender) -> DayCare.Candidate {
        DayCare.Candidate(monID: id, info: EggInfo(eggGroups: groups, genderRate: 4, hatchCounter: 20), gender: gender)
    }

    /// Each half of the rule on its own: a shared egg group with opposite genders, and Ditto with
    /// anything that can make eggs (here a genderless partner that shares no group with it).
    func testCompatibilityAcceptsEachRuleOnItsOwn() {
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["monster"], .female), candidate("b", ["monster", "dragon"], .male)),
                       .compatible)
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["ditto"], .genderless), candidate("b", ["mineral"], .genderless)),
                       .compatible)
    }

    func testCompatibilityRejectsEachBlockedPair() {
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["monster"], .female), candidate("a", ["monster"], .male)), .sameMon)
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["no-eggs"], .male), candidate("b", ["ditto"], .genderless)), .undiscovered)
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["ditto"], .genderless), candidate("b", ["ditto"], .genderless)), .bothDitto)
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["monster"], .female), candidate("b", ["fairy"], .male)), .noSharedEggGroup)
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["monster"], .female), candidate("b", ["monster"], .female)), .genderMismatch)
        XCTAssertEqual(DayCare.compatibility(candidate("a", ["mineral"], .genderless), candidate("b", ["mineral"], .genderless)), .genderMismatch)
    }

    func testMotherIsTheFemaleOrTheNonDittoParent() {
        XCTAssertEqual(DayCare.motherIndex(candidate("a", ["monster"], .male), candidate("b", ["monster"], .female)), 1)
        XCTAssertEqual(DayCare.motherIndex(candidate("a", ["ditto"], .genderless), candidate("b", ["monster"], .male)), 1)
        XCTAssertEqual(DayCare.motherIndex(candidate("a", ["mineral"], .genderless), candidate("b", ["ditto"], .genderless)), 0)
    }

    /// Both clamp bounds and the 2B cap, with the agreed examples.
    func testIncubationTargetScalesByHatchCounterWithinBoundsAndCap() {
        XCTAssertEqual(DayCare.incubationTarget(rarity: .common, hatchCounter: 5), 250_000_000, "Magikarp — floor ×0.5")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .common, hatchCounter: 20), 250_000_000, "20 is still the floor")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .uncommon, hatchCounter: 25), 781_250_000, "Riolu ×0.625")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .rare, hatchCounter: 20), 1_000_000_000, "Bulbasaur")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .rare, hatchCounter: 35), 1_750_000_000, "Eevee ×0.875")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .rare, hatchCounter: 40), 2_000_000_000, "Dratini — full base")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .rare, hatchCounter: 120), 2_000_000_000, "ceiling ×1.0")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .legendary, hatchCounter: 40), DayCare.incubationCap,
                       "Phione — legendary price is 4B, capped")
        XCTAssertEqual(DayCare.incubationTarget(rarity: .common, hatchCounter: nil), FreshEgg.price(guaranteeing: .common),
                       "unknown egg cycles — ×1")
    }

    func testBabySpeciesOverridesAndGenderSplit() {
        XCTAssertEqual(DayCare.babySpecies(motherBaseID: 1, roll: 1), 1)
        XCTAssertEqual(DayCare.babySpecies(motherBaseID: 490, roll: 1), 489, "Manaphy hatches Phione")
        XCTAssertEqual(DayCare.babySpecies(motherBaseID: 29, roll: 0), 29)
        XCTAssertEqual(DayCare.babySpecies(motherBaseID: 29, roll: 1), 32, "Nidoran♀ can hatch Nidoran♂")
        XCTAssertEqual(DayCare.babySpecies(motherBaseID: 314, roll: 1), 313, "Illumise can hatch Volbeat")
    }

    func testInheritedAbilityPassesHiddenSixtyPercentOfTheTime() {
        let options: [PokemonAbility] = [.init(name: "overgrow", isHidden: false), .init(name: "chlorophyll", isHidden: true)]
        XCTAssertEqual(DayCare.inheritedAbility(rolled: "overgrow", options: options, hiddenAbilityParent: true, draw: { 59 }), "chlorophyll")
        XCTAssertEqual(DayCare.inheritedAbility(rolled: "overgrow", options: options, hiddenAbilityParent: true, draw: { 60 }), "overgrow")
        var drew = false
        XCTAssertEqual(DayCare.inheritedAbility(rolled: "overgrow", options: options, hiddenAbilityParent: false,
                                                draw: { drew = true; return 0 }), "overgrow")
        XCTAssertFalse(drew, "no draw without a hidden-ability parent")
    }

    func testInheritedStatsAreDistinctAndCounted() {
        var r = SeededRNG(seed: 4)
        let picks = DayCare.inheritedStats(count: DayCare.destinyKnotInheritedIVCount, draw: { r.next() })
        XCTAssertEqual(picks.count, 5)
        XCTAssertEqual(Set(picks.map(\.0)).count, 5, "no stat copied twice")
        XCTAssertTrue(picks.allSatisfy { (0...1).contains($0.1) })
    }

    func testShinyOddsMatrix() {
        XCTAssertEqual(CompanionStore.shinyDenominator(charmOwned: false, masuda: false), PokemonOdds.shinyDenominator)
        XCTAssertEqual(CompanionStore.shinyDenominator(charmOwned: true, masuda: false), ShinyCharm.shinyDenominator)
        XCTAssertEqual(CompanionStore.shinyDenominator(charmOwned: false, masuda: true), DayCare.masudaShinyDenominator)
        XCTAssertEqual(CompanionStore.shinyDenominator(charmOwned: true, masuda: true), DayCare.masudaCharmShinyDenominator)
        XCTAssertTrue(CompanionStore.rollsShiny(roll: 32, charmOwned: false, masuda: true))
        XCTAssertFalse(CompanionStore.rollsShiny(roll: 32, charmOwned: false, masuda: false))
    }

    func testLegacyGenderIsFixedAndFollowsTheRatio() {
        XCTAssertEqual(StatCalc.legacyGender(monID: "x", genderRate: 4), StatCalc.legacyGender(monID: "x", genderRate: 4))
        XCTAssertEqual(StatCalc.legacyGender(monID: "x", genderRate: 8), .female)
        XCTAssertEqual(StatCalc.legacyGender(monID: "x", genderRate: 0), .male)
        XCTAssertEqual(StatCalc.legacyGender(monID: "x", genderRate: -1), .genderless)
        let saved = Self.mon("y", base: 1, gender: .male)
        XCTAssertEqual(saved.effectiveGender(genderRate: 8), .male, "a hatch roll wins over the fallback")
        XCTAssertNil(Self.mon("z", base: 1, gender: nil).effectiveGender(genderRate: nil), "unknown until the ratio loads")
    }

    // MARK: Drop-off

    func testDropOffChargesFeeLocksParentsAndCopiesTraits() async {
        let s = store(inventory: ["destinyKnot": 1, "everstone": 1])
        let before = s.availableTokens
        let result = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], destinyKnot: true, everstoneMonID: "bulbaF")
        XCTAssertEqual(result, .droppedOff)
        XCTAssertEqual(before - s.availableTokens, DayCare.fee, "only the fee is charged")
        XCTAssertEqual(s.itemCount(.destinyKnot), 0)
        XCTAssertEqual(s.itemCount(.everstone), 0)
        let slot = try! XCTUnwrap(s.dayCareSlot(0))
        XCTAssertEqual(slot.traits.babySpeciesID, 1, "the mother's line")
        XCTAssertEqual(slot.traits.everstoneNature, .adamant)
        XCTAssertTrue(slot.traits.hiddenAbilityParent, "the mother has Chlorophyll")
        XCTAssertTrue(slot.traits.masuda, "Charmander came from a trade")
        XCTAssertEqual(slot.traits.inheritedIVCount, DayCare.destinyKnotInheritedIVCount)
        XCTAssertEqual(slot.target, DayCare.incubationTarget(rarity: .rare, hatchCounter: 20))
        XCTAssertTrue(s.isAtDayCare("bulbaF"))
        XCTAssertTrue(s.isAtDayCare("charM"))
    }

    func testDittoPairHatchesTheOtherParentsLineWithoutMasuda() async {
        let s = store()
        let result = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])
        XCTAssertEqual(result, .droppedOff)
        let slot = try! XCTUnwrap(s.dayCareSlot(0))
        XCTAssertEqual(slot.traits.babySpeciesID, 129)
        XCTAssertFalse(slot.traits.masuda)
        XCTAssertFalse(slot.traits.hiddenAbilityParent)
        XCTAssertEqual(slot.target, 250_000_000, "Magikarp: common, 5 egg cycles → the floor")
    }

    /// The party can change while the drop-off waits on species data. Here a parent becomes the training
    /// Pokémon during that wait — the drop-off must re-check and charge nothing.
    func testDropOffRechecksAfterItsNetworkAwaits() async {
        let provider = DayCareProvider()
        let s = store(provider: provider)
        let before = s.availableTokens
        provider.holdBaseStats()
        let task = Task { await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"]) }
        while !provider.isHeld { await Task.yield() }
        XCTAssertTrue(s.setTrainingSlot(to: "bulbaF"), "not locked yet — the drop-off hasn't finished")
        provider.release()
        let result = await task.value
        XCTAssertEqual(result, .invalidParent)
        XCTAssertEqual(s.availableTokens, before)
        XCTAssertTrue(s.dayCareSlots.isEmpty)
    }

    /// Nidoran♀ with Ditto hatches Nidoran♀ or Nidoran♂; the roll is made at drop-off.
    func testNidoranMotherHatchesEitherNidoran() async {
        var babies = Set<Int>()
        for seed: UInt64 in 1...12 {
            let s = store(seed: seed)
            let result = await s.dropOff(slot: 0, parentIDs: ["nidoF", "ditto"])
            XCTAssertEqual(result, .droppedOff)
            if let baby = s.dayCareSlot(0)?.traits.babySpeciesID { babies.insert(baby) }
        }
        XCTAssertEqual(babies, [29, 32])
    }

    func testEverstoneMustGoToAParent() async {
        let s = store(inventory: ["everstone": 0])
        let missing = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], everstoneMonID: "bulbaF")
        XCTAssertEqual(missing, .missingItem)
        let s2 = store(inventory: ["everstone": 1])
        let stranger = await s2.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], everstoneMonID: "karpM")
        XCTAssertEqual(stranger, .invalidParent)
    }

    /// The baby can be a species the player never owned (a traded mother's line base), so the Pokédex
    /// has no name for it — the slot saves the name at drop-off for the ready notification and screen.
    func testSlotNamesABabyThePokedexDoesNotKnow() async {
        let s = store()
        XCTAssertEqual(s.speciesName(129), "#129", "Magikarp's species has no saved name in this save")
        _ = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])
        let slot = try! XCTUnwrap(s.dayCareSlot(0))
        XCTAssertEqual(s.dayCareBabyName(slot), "Species129")
    }

    func testRejectedDropOffsChargeNothing() async {
        let s = store()
        let before = s.availableTokens
        let incompatible = await s.dropOff(slot: 0, parentIDs: ["bulbaF", "bulbaF2"])
        XCTAssertEqual(incompatible, .incompatible(.genderMismatch))
        let undiscovered = await s.dropOff(slot: 0, parentIDs: ["mewtwo", "ditto"])
        XCTAssertEqual(undiscovered, .incompatible(.undiscovered))
        let training = await s.dropOff(slot: 0, parentIDs: ["train", "bulbaF"])
        XCTAssertEqual(training, .invalidParent, "the training mon can't be dropped off")
        let unowned = await s.dropOff(slot: 1, parentIDs: ["charM", "bulbaF"])
        XCTAssertEqual(unowned, .slotUnavailable, "slot 2 needs the purchase")
        let missingItem = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], destinyKnot: true)
        XCTAssertEqual(missingItem, .missingItem)
        XCTAssertEqual(s.availableTokens, before)
        XCTAssertTrue(s.dayCareSlots.isEmpty)
    }

    func testDropOffNeedsTheFee() async {
        let s = store(tokens: DayCare.fee - 1)
        let result = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"])
        XCTAssertEqual(result, .notEnoughTokens)
    }

    func testOfflineDropOffChargesNothing() async {
        let s = store(provider: DayCareProvider(lineFailures: 1))
        let before = s.availableTokens
        let result = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"])
        XCTAssertEqual(result, .dataUnavailable)
        XCTAssertEqual(s.availableTokens, before)
    }

    func testSecondSlotWorksOnceBoughtAndAParentCantBeInBoth() async {
        let s = store(inventory: ["dayCareSlot": 1])
        XCTAssertEqual(s.dayCareSlotCount, 2)
        let first = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"])
        XCTAssertEqual(first, .droppedOff)
        let reused = await s.dropOff(slot: 1, parentIDs: ["charM", "bulbaF2"])
        XCTAssertEqual(reused, .invalidParent, "Charmander is already incubating in slot 1")
        let second = await s.dropOff(slot: 1, parentIDs: ["ditto", "karpM"])
        XCTAssertEqual(second, .droppedOff)
        let taken = await s.dropOff(slot: 1, parentIDs: ["bulbaF2", "nidoF"])
        XCTAssertEqual(taken, .slotUnavailable)
    }

    // MARK: Incubation and locks

    func testProgressRunsAlongsideTrainingStopsAtTargetAndNeverHatchesItself() async {
        let s = store()
        _ = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])   // 250M
        use(s, 0)
        use(s, 100_000_000)
        XCTAssertEqual(s.dayCareSlot(0)?.progress, 100_000_000)
        XCTAssertEqual(mon(s, "train")?.usedAtStage, 100_000_000, "training keeps all its growth")
        XCTAssertTrue(s.isAtDayCare("karpM"))
        use(s, 400_000_000)
        XCTAssertEqual(s.dayCareSlot(0)?.progress, 250_000_000, "stops at the target")
        XCTAssertEqual(s.dayCareSlot(0)?.isReady, true)
        XCTAssertFalse(s.isAtDayCare("karpM"), "parents unlock once the egg is ready")
        XCTAssertEqual(s.state.trainingSlotID, "train", "a ready egg waits for the player")
        XCTAssertNil(s.state.pendingDayCareEgg)
    }

    func testIncubatingParentsRefuseTrainingTradesAndItems() async {
        let s = store(inventory: ["protein": 1, "bottlecapSilver": 1])
        _ = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"])
        XCTAssertFalse(s.setTrainingSlot(to: "bulbaF"))
        XCTAssertFalse(s.benchedParty.contains { $0.id == "bulbaF" }, "not offered for trade")
        XCTAssertFalse(s.canUseVitamin(.protein, on: "bulbaF"))
        XCTAssertFalse(s.useVitamin(.protein, for: "bulbaF"))
        XCTAssertFalse(s.canStartHyperTraining(.bottlecapSilver, target: .stat(.hp), on: "bulbaF"))
        let learnset = [LearnableMove(moveID: 45, method: .egg, level: 0)]
        XCTAssertFalse(s.canLearnLevelUpMove(45, for: "bulbaF", learnset: learnset))
        // The same actions are open for a benched mon that isn't at the Day Care.
        XCTAssertTrue(s.canUseVitamin(.protein, on: "bulbaF2"))
        XCTAssertTrue(s.canLearnLevelUpMove(45, for: "bulbaF2", learnset: learnset))
    }

    func testTradeRemovingAnIncubatingParentCancelsTheSlot() async {
        let s = store(inventory: ["everstone": 1])
        _ = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], everstoneMonID: "charM")
        XCTAssertTrue(s.removeFromParty("charM"))
        XCTAssertTrue(s.dayCareSlots.isEmpty)
        XCTAssertFalse(s.isAtDayCare("bulbaF"))
        XCTAssertEqual(s.itemCount(.everstone), 1, "attached item returned")
    }

    // MARK: Cancel / discard

    func testCancelUnlocksParentsReturnsItemsAndKeepsTheFee() async {
        let s = store(inventory: ["destinyKnot": 1, "everstone": 1])
        _ = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], destinyKnot: true, everstoneMonID: "bulbaF")
        let afterFee = s.availableTokens
        XCTAssertFalse(s.discardDayCareEgg(slot: 0), "nothing to discard while incubating")
        XCTAssertTrue(s.cancelDayCare(slot: 0))
        XCTAssertTrue(s.dayCareSlots.isEmpty)
        XCTAssertFalse(s.isAtDayCare("bulbaF"))
        XCTAssertFalse(s.isAtDayCare("charM"))
        XCTAssertEqual(s.itemCount(.destinyKnot), 1)
        XCTAssertEqual(s.itemCount(.everstone), 1)
        XCTAssertEqual(s.availableTokens, afterFee, "the fee isn't refunded")
    }

    func testReadyEggCanBeDiscardedButNotCancelled() async {
        let s = store()
        _ = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])
        use(s, 0); use(s, 300_000_000)
        XCTAssertFalse(s.cancelDayCare(slot: 0))
        XCTAssertTrue(s.discardDayCareEgg(slot: 0))
        XCTAssertTrue(s.dayCareSlots.isEmpty)
    }

    // MARK: Hatching

    func testHatchThisEggIsBlockedWhileAnEggIsInTheActiveSlot() async {
        let s = store()
        _ = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])
        use(s, 0); use(s, 300_000_000)
        XCTAssertTrue(s.buyEgg(nil), "puts an ordinary egg in the active slot")
        XCTAssertFalse(s.canHatchDayCareEgg)
        XCTAssertFalse(s.hatchDayCareEgg(slot: 0))
        XCTAssertNotNil(s.dayCareSlot(0), "the Day Care egg keeps waiting")
    }

    /// The full trip: drop off → incubate → "Hatch this egg" → the normal 5M hatch, with inheritance.
    func testDayCareEggHatchesTheBabyWithInheritedTraits() async {
        let s = store(inventory: ["everstone": 1])
        _ = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"], everstoneMonID: "bulbaF")
        use(s, 0)
        use(s, DayCare.incubationTarget(rarity: .rare, hatchCounter: 20))
        XCTAssertTrue(s.hatchDayCareEgg(slot: 0))
        XCTAssertNil(s.state.trainingSlotID, "the training Pokémon went to the PC")
        XCTAssertTrue(s.party.contains { $0.id == "train" })
        XCTAssertTrue(s.dayCareSlots.isEmpty, "the slot frees up")
        XCTAssertEqual(s.state.pendingHatchID, 1)
        XCTAssertTrue(s.activeEggIsFromDayCare)

        use(s, DayCare.incubationTarget(rarity: .rare, hatchCounter: 20) + PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        let baby = try! XCTUnwrap(s.trainingMon)
        XCTAssertEqual(baby.baseID, 1)
        XCTAssertEqual(baby.nature, .adamant, "Everstone nature")
        XCTAssertEqual(baby.knownMoves.first, 113, "the egg move a parent knew")
        XCTAssertNotNil(baby.gender)
        XCTAssertNil(baby.dittoDisguise)
        XCTAssertNil(s.state.pendingDayCareEgg, "consumed by the hatch")
        let ivs = try! XCTUnwrap(baby.ivs)
        let fromParents = [ivs.hp, ivs.attack, ivs.defense, ivs.specialAttack, ivs.specialDefense, ivs.speed]
            .filter { $0 == 31 || $0 == 0 }.count
        XCTAssertGreaterThanOrEqual(fromParents, DayCare.inheritedIVCount, "3 IVs copied from the 31/0 parents")
    }

    /// Two slots incubate off the same usage; both eggs can be ready, but only one goes to the active
    /// slot — the second waits until the first has hatched.
    func testBothSlotsIncubateTogetherAndOnlyOneEggHatchesAtATime() async {
        let s = store(inventory: ["dayCareSlot": 1])
        _ = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"])   // 1B
        _ = await s.dropOff(slot: 1, parentIDs: ["ditto", "karpM"])    // 250M
        use(s, 0)
        use(s, 400_000_000)
        XCTAssertEqual(s.dayCareSlot(1)?.isReady, true)
        XCTAssertEqual(s.dayCareSlot(0)?.progress, 400_000_000, "the same usage counts for both slots")
        use(s, 1_000_000_000)
        XCTAssertTrue(s.dayCareSlots.allSatisfy(\.isReady))

        XCTAssertTrue(s.hatchDayCareEgg(slot: 1))
        XCTAssertFalse(s.canHatchDayCareEgg)
        XCTAssertFalse(s.hatchDayCareEgg(slot: 0), "one egg in the active slot at a time")
        use(s, 1_000_000_000 + PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.trainingMon?.baseID, 129)
        XCTAssertTrue(s.hatchDayCareEgg(slot: 0), "allowed again once the first egg hatched")
        XCTAssertEqual(s.state.pendingHatchID, 1)
    }

    func testSecondSlotIsAOneTimeShopPurchase() {
        let s = store()
        XCTAssertEqual(s.dayCareSlotCount, 1)
        XCTAssertTrue(s.buy(.dayCareSlot))
        XCTAssertEqual(s.dayCareSlotCount, 2)
        XCTAssertEqual(s.maxBuyCount(.dayCareSlot), 0, "permanent — can't be bought twice")
        XCTAssertEqual(s.state.spentTokens, DayCare.secondSlotPrice)
    }

    func testOrdinaryHatchAlsoRollsAGender() async {
        let s = store(training: false)
        use(s, 0)
        use(s, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.trainingMon?.baseID, 4, "the stub's random roll")
        XCTAssertNotNil(s.trainingMon?.gender)
    }

    /// The 60% hidden-ability branch is wired into the real hatch: across seeds, a hidden-ability mother
    /// gives both outcomes, and a mother without one never gives it (Bulbasaur's normal roll is 10:1).
    func testHatchPassesTheHiddenAbilitySometimes() async {
        func hatchAbility(seed: UInt64, mother: String) async -> String? {
            let s = store(seed: seed) { st in
                if let i = st.party.firstIndex(where: { $0.id == "bulbaF2" }) { st.party[i].ability = "overgrow" }
            }
            _ = await s.dropOff(slot: 0, parentIDs: ["ditto", mother])
            use(s, 0); use(s, 2_000_000_000)
            _ = s.hatchDayCareEgg(slot: 0)
            use(s, 2_000_000_000 + PokemonBalance.eggHatchThreshold)
            await s.hatchIfNeeded()
            return s.trainingMon?.ability
        }
        var withHidden = Set<String>()
        for seed: UInt64 in 1...12 { if let a = await hatchAbility(seed: seed, mother: "bulbaF") { withHidden.insert(a) } }
        XCTAssertEqual(withHidden, ["overgrow", "chlorophyll"])
        var hiddenCount = 0
        for seed: UInt64 in 1...12 where await hatchAbility(seed: seed, mother: "bulbaF2") == "chlorophyll" { hiddenCount += 1 }
        XCTAssertLessThan(hiddenCount, 4, "without a hidden-ability parent only the rare normal roll gives it")
    }

    /// A hatch whose line fetch fails clears the pre-roll; the retry must hatch the parents' species,
    /// not a random one.
    func testFailedHatchRetryKeepsTheDayCareSpecies() async {
        let provider = DayCareProvider()
        let s = store(provider: provider)
        _ = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])
        use(s, 0); use(s, 300_000_000)
        XCTAssertTrue(s.hatchDayCareEgg(slot: 0))
        provider.failLines(1_000)
        use(s, 300_000_000 + PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNil(s.trainingMon, "offline — the egg is kept")
        XCTAssertNil(s.state.pendingHatchID, "the failed hatch cleared the pre-roll")
        provider.failLines(0)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.trainingMon?.baseID, 129, "the retry hatches the parents' species, not a random roll")
    }

    func testRegionChangeDoesNotRerollADayCareEgg() async {
        let s = store()
        _ = await s.dropOff(slot: 0, parentIDs: ["ditto", "karpM"])
        use(s, 0); use(s, 300_000_000)
        XCTAssertTrue(s.hatchDayCareEgg(slot: 0))
        s.setEggRegion(.johto)
        XCTAssertEqual(s.state.pendingHatchID, 129)
        XCTAssertNotNil(s.state.pendingDayCareEgg)
    }

    // MARK: Saves

    func testSaveRoundTripKeepsTheDayCare() async throws {
        let s = store()
        _ = await s.dropOff(slot: 0, parentIDs: ["charM", "bulbaF"])
        let data = try s.exportedSaveData(appVersion: "test", deviceName: "Mac")
        let imported = try SaveTransfer.decode(data).state
        XCTAssertEqual(imported.dayCare, s.state.dayCare)
    }

    func testSanitizeCancelsSlotsThatCouldNotComeFromPlay() {
        let traits = InheritedTraits(babySpeciesID: 1, parentIVs: [StatSpread(), StatSpread()], inheritedIVCount: 3,
                                    everstoneNature: nil, hiddenAbilityParent: false, parentMoves: [], masuda: false)
        var st = CompanionState()
        st.party = [Self.mon("a", base: 1, gender: .female), Self.mon("b", base: 4, gender: .male),
                    Self.mon("c", base: 1, gender: .female)]
        st.trainingSlotID = "c"
        st.dayCare = [
            DayCareSlot(slot: 0, parentIDs: ["a", "gone"], traits: traits, babyRarity: .rare, target: 10,
                        usedEverstone: true),                                           // missing parent
            DayCareSlot(slot: 1, parentIDs: ["a", "b"], traits: traits, babyRarity: .rare, target: 10),   // not bought
        ]
        let cleaned = SaveTransfer.sanitized(st)
        XCTAssertTrue(cleaned.dayCare.isEmpty)
        XCTAssertEqual(cleaned.inventory[ItemKind.everstone.rawValue], 1, "attached item returned")

        st.dayCare = [DayCareSlot(slot: 0, parentIDs: ["a", "c"], traits: traits, babyRarity: .rare, target: 10)]
        XCTAssertTrue(SaveTransfer.sanitized(st).dayCare.isEmpty, "the training mon can't be incubating")

        st.dayCare = [DayCareSlot(slot: 0, parentIDs: ["a", "b"], traits: traits, babyRarity: .rare,
                                  target: Int.max, progress: Int.max)]
        let clamped = SaveTransfer.sanitized(st).dayCare.first
        XCTAssertEqual(clamped?.target, DayCare.incubationCap)
        XCTAssertEqual(clamped?.progress, DayCare.incubationCap)

        st.pendingDayCareEgg = traits
        XCTAssertNil(SaveTransfer.sanitized(st).pendingDayCareEgg, "no Day Care egg while a mon is training")
        st.trainingSlotID = nil
        XCTAssertEqual(SaveTransfer.sanitized(st).pendingHatchID, 1, "the egg keeps its parents' species")
    }
}
