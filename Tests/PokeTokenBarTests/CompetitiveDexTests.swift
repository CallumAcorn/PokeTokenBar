import XCTest
@testable import PokeTokenBar

/// The bundled competitive catalog (`Resources/competitive-gen5.json`) and the dex questions asked of it.
final class CompetitiveDexTests: XCTestCase {
    private let dex = CompetitiveDex.shared

    // MARK: - Bundled data

    func testBundledCatalogCoversEverySupportedSpecies() {
        XCTAssertEqual(dex.entries.count, PokemonAssets.animatedSpeciesIDs.count)
        XCTAssertEqual(Set(dex.entries.keys), Set(PokemonAssets.animatedSpeciesIDs))
    }

    func testEveryEntryIsUsable() {
        for entry in dex.all {
            XCTAssertNotNil(dex.entries[entry.baseID], "#\(entry.id) line base #\(entry.baseID) missing")
            XCTAssertFalse(entry.types.isEmpty, "#\(entry.id) has no types")
            XCTAssertNotNil(entry.names["en"], "#\(entry.id) has no English name")
            XCTAssertFalse(entry.build.ability.isEmpty, "#\(entry.id) has no ability")
            XCTAssertTrue((1...4).contains(entry.build.moves.count), "#\(entry.id) has \(entry.build.moves.count) moves")
            XCTAssertEqual(Set(entry.build.moves).count, entry.build.moves.count, "#\(entry.id) repeats a move")
            if let adjusted = entry.adjusted, entry.tier != .f {
                XCTAssertGreaterThan(entry.tier, adjusted.from, "#\(entry.id) adjustment must lower the tier")
            }
        }
    }

    /// Names resolve per language the same way species names do elsewhere (pt falls back to English).
    func testNamesFollowAppLanguage() throws {
        let pikachu = try XCTUnwrap(dex.entries[25])
        XCTAssertEqual(pikachu.name(.en), "Pikachu")
        XCTAssertEqual(pikachu.name(.ko), "피카츄")
        XCTAssertEqual(pikachu.name(.pt), "Pikachu")
    }

    // MARK: - Rarity

    /// Rarity belongs to the line: Butterfree reads Common because Caterpie is what hatches.
    func testRarityComesFromTheLineBase() {
        XCTAssertEqual(dex.rarity(of: 10), .common)   // Caterpie
        XCTAssertEqual(dex.rarity(of: 12), .common)   // Butterfree
        XCTAssertEqual(dex.rarity(of: 149), .rare)    // Dragonite ← Dratini
        XCTAssertEqual(dex.rarity(of: 150), .legendary)
        XCTAssertEqual(dex.rarity(of: 151), .legendary) // mythical
        XCTAssertNil(dex.rarity(of: 9999))
    }

    // MARK: - Tiers

    func testLinePeakIsTheBestTierInTheLine() {
        XCTAssertEqual(dex.linePeak(of: 4)?.id, 6)    // Charmander → Charizard
        XCTAssertEqual(dex.linePeak(of: 6)?.id, 6)
        XCTAssertNil(dex.linePeak(of: 9999))
    }

    /// Cloyster is Uber on Smogon, but its rated sets are built on Shell Smash, which only Shellder
    /// learns (by level-up) in BW — an in-app Cloyster can't run it. Its egg moves (Icicle Spear,
    /// Rock Blast, Rapid Spin) *are* available, so only the one move is lost: one tier down.
    func testAdjustmentRecordsTheMovesTheAppCannotTeach() throws {
        let cloyster = try XCTUnwrap(dex.entries[91])
        let adjusted = try XCTUnwrap(cloyster.adjusted)
        XCTAssertEqual(adjusted.from, .s)
        XCTAssertEqual(cloyster.tier, .a)
        XCTAssertEqual(adjusted.reasons, [.moves])
        XCTAssertEqual(adjusted.lostMoves, [504], "only Shell Smash")   // PokéAPI move id
    }

    /// Egg moves count as learnable: Tyranitar's Pursuit is a Larvitar egg move, so its OU rating
    /// stands unadjusted and the build may use it.
    func testEggMovesFromTheLineCountAsLearnable() throws {
        let tyranitar = try XCTUnwrap(dex.entries[248])
        XCTAssertEqual(tyranitar.tier, .a)
        XCTAssertNil(tyranitar.adjusted)
        XCTAssertTrue(tyranitar.build.moves.contains(228), "Pursuit")
    }

    /// Every suggested move must be one this species can be taught — the move lists on the same dex
    /// screen. Spot-checked against PokéAPI's BW learnset: Cloyster's own list has no Shell Smash.
    func testBuildsOnlyUseTheSpeciesOwnMoves() throws {
        let cloyster = try XCTUnwrap(dex.entries[91])
        XCTAssertFalse(cloyster.build.moves.contains(504), "Shell Smash is Shellder-only in BW")
    }

    // MARK: - Alternatives

    func testAlternativesAreBetterSameTypeAndOutsideTheLine() throws {
        let charizard = try XCTUnwrap(dex.entries[6])
        let alts = dex.alternatives(to: 6)
        XCTAssertEqual(alts.count, 10)
        for alt in alts {
            XCTAssertLessThan(alt.tier, charizard.tier, "\(alt.id) isn't rated higher")
            XCTAssertTrue(alt.types.contains(where: charizard.types.contains), "\(alt.id) shares no type")
            XCTAssertNotEqual(alt.baseID, charizard.baseID, "\(alt.id) is in Charizard's own line")
        }
        // The closest matches lead: Fire special attackers rated above D (Chandelure, Heatran, …).
        let first = try XCTUnwrap(alts.first)
        XCTAssertTrue(first.types.contains(.fire))
        XCTAssertEqual(first.category, .special)
        XCTAssertTrue(alts.contains { $0.id == 609 }, "Chandelure missing")
    }

    /// An unevolved species is compared against what its line becomes, not against its own F.
    func testAlternativesForUnevolvedUseTheLinePeak() {
        XCTAssertEqual(dex.alternatives(to: 4).map(\.id), dex.alternatives(to: 6).map(\.id))
    }

    func testNothingRatesAboveTheTopTier() {
        XCTAssertTrue(dex.alternatives(to: 150).isEmpty)   // Mewtwo, S
        XCTAssertTrue(dex.alternatives(to: 9999).isEmpty)
    }

    /// Ranking order on a hand-built catalog: main type beats lean, lean beats role, tier breaks ties.
    func testAlternativesRanking() throws {
        func row(_ id: Int, _ types: [String], _ tier: String, _ role: String, _ category: String) -> String {
            let typeList = types.map { "\"\($0)\"" }.joined(separator: ",")
            return """
            {"id":\(id),"names":{"en":"M\(id)"},"captureRate":45,"legendary":false,"mythical":false,"baseID":\(id),
             "types":[\(typeList)],"smogonTier":"OU","tier":"\(tier)","role":"\(role)","category":"\(category)",
             "build":{"ability":"blaze","nature":"timid","evs":{"hp":0,"attack":0,"defense":0,"specialAttack":252,
             "specialDefense":0,"speed":252},"moves":[53]},"source":{"kind":"auto"}}
            """
        }
        let json = """
        {"species":[
        \(row(1, ["fire", "flying"], "D", "attacker", "special")),
        \(row(2, ["flying"], "A", "attacker", "special")),
        \(row(3, ["fire"], "C", "support", "physical")),
        \(row(4, ["fire"], "B", "setup", "special")),
        \(row(5, ["fire"], "A", "setup", "special")),
        \(row(6, ["water"], "S", "attacker", "special")),
        \(row(7, ["fire"], "E", "attacker", "special"))
        ]}
        """
        let small = try CompetitiveDex(json: Data(json.utf8))
        // 5 and 4 (main type + lean) beat 3 (main type only), which beats 2 (secondary type only);
        // 5 beats 4 on tier. 6 shares no type; 7 is rated lower.
        XCTAssertEqual(small.alternatives(to: 1).map(\.id), [5, 4, 3, 2])
        XCTAssertEqual(small.alternatives(to: 1, limit: 2).map(\.id), [5, 4])
    }

    func testCorruptCatalogThrows() {
        XCTAssertThrowsError(try CompetitiveDex(json: Data("{}".utf8)))
    }
}

/// "Show all" in the dex: every catalog species, met ones from the save and the rest as placeholders.
final class DexShowAllTests: XCTestCase {
    private typealias Species = CompanionStore.DexSpecies
    private let met = [
        Species(id: 4, name: "My Charmander", rarity: .rare, isShiny: true, baseID: 4),
        Species(id: 25, name: "Pika", rarity: .common, isShiny: false, baseID: 172),
    ]

    func testOffShowsOnlyMetSpecies() {
        let list = CompanionStore.dexList(seen: met, includingUnseen: false, catalog: .shared, language: .en)
        XCTAssertEqual(list.map(\.id), [4, 25])
    }

    func testOnListsEverySpeciesInDexOrder() {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true, catalog: .shared, language: .en)
        XCTAssertEqual(list.map(\.id), Array(PokemonAssets.animatedSpeciesIDs))
        XCTAssertEqual(list.filter(\.isSeen).map(\.id), [4, 25])
    }

    /// A met species keeps the save's own entry — its stored name and shiny flag aren't replaced.
    func testMetSpeciesKeepTheirOwnEntry() throws {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true, catalog: .shared, language: .en)
        let charmander = try XCTUnwrap(list.first { $0.id == 4 })
        XCTAssertEqual(charmander.name, "My Charmander")
        XCTAssertTrue(charmander.isShiny)
    }

    /// Placeholders take name, rarity and line from the catalog, in the app's language, never shiny.
    func testUnseenPlaceholderComesFromTheCatalog() throws {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true, catalog: .shared, language: .ko)
        let dragonite = try XCTUnwrap(list.first { $0.id == 149 })
        XCTAssertFalse(dragonite.isSeen)
        XCTAssertFalse(dragonite.isShiny)
        XCTAssertEqual(dragonite.name, "망나뇽")
        XCTAssertEqual(dragonite.rarity, .rare)
        XCTAssertEqual(dragonite.baseID, 147)
    }

    func testEmptyCatalogFallsBackToMetSpecies() {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true,
                                          catalog: CompetitiveDex(entries: [:]), language: .en)
        XCTAssertEqual(list.map(\.id), [4, 25])
    }
}
