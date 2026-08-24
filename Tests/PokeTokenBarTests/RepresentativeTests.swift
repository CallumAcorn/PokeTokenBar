import XCTest
@testable import PokeTokenBar

/// Pinning a representative species to the menu bar (#158), reimplemented on this fork's
/// PC/party model rather than cherry-picked.
///
/// Upstream's version reads `state.active` — a single companion. Here the same concept sits on
/// top of `party` + `trainingSlotID`, and ownership is a lookup in `dexUnlocked` (a species-level
/// unlock map this fork already keeps) instead of a scan over the dex and the active mon.
///
/// The two features are orthogonal by design: the representative decides **what the menu bar
/// draws**, the training slot decides **which party member receives usage**. Pinning must not
/// disturb progression, and progression must not silently change the pin.
final class RepresentativeTests: XCTestCase {

    private func state(unlocked: [Int], shiny: Set<Int> = []) -> CompanionState {
        var s = CompanionState()
        for id in unlocked {
            s.dexUnlocked[id] = DexUnlock(baseID: id, rarity: .common, names: nil,
                                          isShiny: shiny.contains(id))
        }
        return s
    }

    // MARK: ownership

    func testOwnsOnlyUnlockedSpecies() {
        let s = state(unlocked: [1, 4])
        XCTAssertTrue(s.ownsSpecies(1))
        XCTAssertTrue(s.ownsSpecies(4))
        XCTAssertFalse(s.ownsSpecies(7))
    }

    func testShinyOwnershipIsPerSpecies() {
        let s = state(unlocked: [1, 4], shiny: [4])
        XCTAssertFalse(s.ownsShinySpecies(1))
        XCTAssertTrue(s.ownsShinySpecies(4))
        XCTAssertFalse(s.ownsShinySpecies(7), "a species you do not own cannot be shiny-owned")
    }

    // MARK: reconciliation

    /// A hand-edited save, or a species that left via trade, must not leave a ghost pinned to the
    /// menu bar forever.
    func testReconcileClearsASelectionNoLongerOwned() {
        var s = state(unlocked: [1])
        s.representativeSpeciesID = 999
        s.reconcileRepresentativeSelection()
        XCTAssertNil(s.representativeSpeciesID)
    }

    func testReconcileKeepsAnOwnedSelection() {
        var s = state(unlocked: [1])
        s.representativeSpeciesID = 1
        s.reconcileRepresentativeSelection()
        XCTAssertEqual(s.representativeSpeciesID, 1)
    }

    /// `sanitized` backfills `dexUnlocked` from `dex`/`party` before reconciling. Running the
    /// reconcile first would read a map that is still behind and clear a pin the user legitimately
    /// owns — the ordering is load-bearing and a normal save cannot detect it, because backfill has
    /// nothing to do there.
    func testSanitizeReconcilesAfterBackfillingOwnership() {
        var s = CompanionState()
        s.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common,
                          caughtAt: nil, isShiny: false, nature: nil, names: nil,
                          monID: "m1", source: .egg)]
        s.dexUnlocked = [:]                 // deliberately behind, which is what backfill repairs
        s.representativeSpeciesID = 2       // owned via the dex entry above

        let clean = SaveTransfer.sanitized(s)
        XCTAssertEqual(clean.representativeSpeciesID, 2,
                       "reconcile ran before backfill and discarded a legitimately owned pin")
    }
}

/// The pin travels with a save, matching upstream's classification: it names a species you own,
/// and ownership travels too.
extension RepresentativeTests {
    func testPinSurvivesExportAndImport() throws {
        var s = state(unlocked: [1, 4])
        s.representativeSpeciesID = 4

        let data = try SaveTransfer.encode(state: s, appVersion: "test", deviceName: "dev",
                                           now: Date(timeIntervalSince1970: 1_700_000_000))
        let envelope = try SaveTransfer.decode(data)
        XCTAssertEqual(envelope.state.representativeSpeciesID, 4)
    }

    /// A save that pins a species its own state does not contain must not import the pin.
    func testImportDropsAPinTheSaveDoesNotOwn() throws {
        var s = state(unlocked: [1])
        s.representativeSpeciesID = 4          // not unlocked in this state

        let data = try SaveTransfer.encode(state: s, appVersion: "test", deviceName: "dev",
                                           now: Date(timeIntervalSince1970: 1_700_000_000))
        let envelope = try SaveTransfer.decode(data)
        XCTAssertNil(envelope.state.representativeSpeciesID,
                     "an unowned pin must not survive import")
    }
}
