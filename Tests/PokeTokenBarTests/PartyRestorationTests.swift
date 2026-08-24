import XCTest
@testable import PokeTokenBar

/// Restoring individuals that the old model discarded on graduation.
///
/// The current model keeps a graduated Pokémon in the PC and only frees the training slot. The old
/// one discarded `active` outright, and the `active` → `party` migration carried only the mon alive
/// at that moment — so anything graduated earlier survives as a catch-log row with no PC entry,
/// which contradicts what the new model promises.
///
/// Measured on a real save: a Seedot line graduated on 21 Aug was in the Pokédex and in
/// `collectedFinals`, but absent from the PC.
final class PartyRestorationTests: XCTestCase {

    private func entry(base: Int, chain: [Int], monID: String? = nil,
                       shiny: Bool = false, rarity: Rarity = .common) -> DexEntry {
        DexEntry(baseID: base, finalID: chain.last ?? base, chainOrder: chain, rarity: rarity,
                 caughtAt: Date(timeIntervalSince1970: 1_700_000_000), isShiny: shiny,
                 nature: nil, names: nil, monID: monID, source: .egg)
    }

    private func mon(id: String, base: Int, chain: [Int]) -> MonState {
        MonState(id: id, baseID: base, pathIDs: chain, stageIndex: chain.count - 1,
                 usedAtStage: 0, rarity: .common, totalForms: chain.count)
    }

    func testRestoresAGraduatedIndividualMissingFromThePC() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 273, chain: [273, 274, 275])])
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.baseID, 273)
        XCTAssertEqual(restored.first?.currentID, 275, "restored at its final form")
        XCTAssertEqual(restored.first?.totalForms, 3)
    }

    /// A log row pointing at a live party member is already represented — restoring it would
    /// duplicate the Pokémon currently being trained.
    func testDoesNotDuplicateALiveIndividual() {
        let live = mon(id: "abc", base: 163, chain: [163, 164])
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [live], dex: [entry(base: 163, chain: [163, 164], monID: "abc")])
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, "abc")
    }

    /// The case that makes the `monID != nil` guard load-bearing: a row that names an individual
    /// which is no longer in the party means it was **traded away**, not discarded on graduation.
    /// Restoring it would hand the user back a Pokémon they gave to someone else.
    func testDoesNotResurrectATradedAwayIndividual() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 25, chain: [172, 25, 26], monID: "gone")])
        XCTAssertTrue(restored.isEmpty, "a traded individual must not come back")
    }

    /// An empty chain cannot make a decodable MonState — `MonState.init(from:)` rejects empty
    /// pathIDs, so restoring one would create state that fails to load next launch.
    func testSkipsAnEmptyChain() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 1, chain: [])])
        XCTAssertTrue(restored.isEmpty)
    }

    func testRestoredIndividualCarriesShinyAndRarity() {
        let restored = CompanionState.restoredPartyFromCatchLog(
            party: [], dex: [entry(base: 133, chain: [133, 134], shiny: true, rarity: .rare)])
        XCTAssertEqual(restored.first?.isShiny, true)
        XCTAssertEqual(restored.first?.rarity, .rare)
    }

    /// Restoration runs on load, and must not change which Pokémon is being trained.
    func testSanitizeRestoresWithoutTouchingTheTrainingSlot() {
        var s = CompanionState()
        let live = mon(id: "live", base: 163, chain: [163, 164])
        s.party = [live]
        s.trainingSlotID = "live"
        s.dex = [entry(base: 163, chain: [163, 164], monID: "live"),
                 entry(base: 273, chain: [273, 274, 275])]

        let clean = SaveTransfer.sanitized(s)
        XCTAssertEqual(clean.party.count, 2, "the graduated individual should be back in the PC")
        XCTAssertEqual(clean.trainingSlotID, "live", "restoration must not change what is training")
        XCTAssertTrue(clean.dexUnlocked.keys.contains(275),
                      "restored individuals fold into dexUnlocked — restoration runs before backfill")
    }
}
