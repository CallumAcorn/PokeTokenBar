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
            XCTAssertFalse(entry.build.ability.isEmpty, "#\(entry.id) has no ability")
            XCTAssertTrue((1...4).contains(entry.build.moves.count), "#\(entry.id) has \(entry.build.moves.count) moves")
            XCTAssertEqual(Set(entry.build.moves).count, entry.build.moves.count, "#\(entry.id) repeats a move")
            if let adjusted = entry.adjusted, entry.tier != .f {
                XCTAssertGreaterThan(entry.tier, adjusted.from, "#\(entry.id) adjustment must lower the tier")
            }
        }
    }

    /// The bundle must carry no Pokémon names: they are trademarked content the app fetches from
    /// PokéAPI at runtime and never ships. Checked on the raw file so a regenerated bundle that
    /// brings them back fails here, even though the decoder would silently ignore the key.
    func testBundleCarriesNoPokemonNames() throws {
        let url = try XCTUnwrap(CompetitiveDex.resourceURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let species = try XCTUnwrap(root["species"] as? [[String: Any]])
        XCTAssertFalse(species.isEmpty)
        for entry in species {
            XCTAssertNil(entry["names"], "#\(entry["id"] ?? "?") carries names")
            XCTAssertNil(entry["name"], "#\(entry["id"] ?? "?") carries a name")
        }
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

    /// Linoone's rated set needs Extreme Speed, which it only ever had from an event — no game
    /// teaches it. That one lost move lowers it one tier, and the move is recorded so the dex can
    /// name it.
    func testAdjustmentRecordsTheMovesTheAppCannotTeach() throws {
        let linoone = try XCTUnwrap(dex.entries[264])
        let adjusted = try XCTUnwrap(linoone.adjusted)
        XCTAssertEqual(adjusted.from, .d)
        XCTAssertEqual(linoone.tier, .e)
        XCTAssertEqual(adjusted.reasons, [.moves])
        XCTAssertEqual(adjusted.lostMoves, [245], "Extreme Speed")   // PokéAPI move id
    }

    /// Older-game moves count: Blissey's OU sets need Seismic Toss, a Gen 3 tutor move (Chansey's)
    /// that reaches Gen 5 only by transfer. It keeps its A.
    func testGen3And4MovesCountAsLearnable() throws {
        let blissey = try XCTUnwrap(dex.entries[242])
        XCTAssertEqual(blissey.tier, .a)
        XCTAssertNil(blissey.adjusted)
        XCTAssertTrue(blissey.build.moves.contains(69), "Seismic Toss")
    }

    /// Earlier-stage level-up, egg and tutor moves all count: Cloyster's Uber set runs on Shell Smash
    /// (Shellder level-up) and Icicle Spear/Rock Blast (Shellder egg moves), so it keeps its S.
    func testMovesFromEarlierStagesCountAsLearnable() throws {
        let cloyster = try XCTUnwrap(dex.entries[91])
        XCTAssertEqual(cloyster.tier, .s)
        XCTAssertNil(cloyster.adjusted)
        XCTAssertTrue(cloyster.build.moves.contains(504), "Shell Smash")
        XCTAssertTrue(cloyster.build.moves.contains(350), "Rock Blast")
    }

    /// Tutor moves count: Tyranitar's build may use Superpower (a Black 2/White 2 tutor).
    func testTutorMovesCountAsLearnable() throws {
        let tyranitar = try XCTUnwrap(dex.entries[248])
        XCTAssertEqual(tyranitar.tier, .a)
        XCTAssertNil(tyranitar.adjusted)
        XCTAssertTrue(tyranitar.build.moves.contains(276), "Superpower")
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
            {"id":\(id),"captureRate":45,"legendary":false,"mythical":false,"baseID":\(id),
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
        let list = CompanionStore.dexList(seen: met, includingUnseen: false, catalog: .shared)
        XCTAssertEqual(list.map(\.id), [4, 25])
    }

    func testOnListsEverySpeciesInDexOrder() {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true, catalog: .shared)
        XCTAssertEqual(list.map(\.id), Array(PokemonAssets.animatedSpeciesIDs))
        XCTAssertEqual(list.filter(\.isSeen).map(\.id), [4, 25])
    }

    /// A met species keeps the save's own entry — its stored name and shiny flag aren't replaced.
    func testMetSpeciesKeepTheirOwnEntry() throws {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true, catalog: .shared)
        let charmander = try XCTUnwrap(list.first { $0.id == 4 })
        XCTAssertEqual(charmander.name, "My Charmander")
        XCTAssertTrue(charmander.isShiny)
    }

    /// Placeholders take rarity and line from the catalog and are never shiny. The name is only the
    /// Dex number: the bundle carries no Pokémon names, they are fetched from PokéAPI on display.
    func testUnseenPlaceholderComesFromTheCatalog() throws {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true, catalog: .shared)
        let dragonite = try XCTUnwrap(list.first { $0.id == 149 })
        XCTAssertFalse(dragonite.isSeen)
        XCTAssertFalse(dragonite.isShiny)
        XCTAssertEqual(dragonite.name, "#149")
        XCTAssertEqual(dragonite.rarity, .rare)
        XCTAssertEqual(dragonite.baseID, 147)
    }

    func testEmptyCatalogFallsBackToMetSpecies() {
        let list = CompanionStore.dexList(seen: met, includingUnseen: true,
                                          catalog: CompetitiveDex(entries: [:]))
        XCTAssertEqual(list.map(\.id), [4, 25])
    }
}

/// Names for species shown from the catalog. The bundle carries none, so they come from the save
/// for owned species and from PokéAPI for the rest.
@MainActor
final class CatalogSpeciesNameTests: XCTestCase {
    private final class NamesProvider: PokeProviding, @unchecked Sendable {
        nonisolated(unsafe) var requested: [Int] = []
        let names: [Int: [String: String]]
        init(_ names: [Int: [String: String]]) { self.names = names }
        func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.unsupportedURL) }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
        func speciesNames(speciesID: Int) async throws -> [String: String] {
            requested.append(speciesID)
            guard let n = names[speciesID] else { throw URLError(.notConnectedToInternet) }
            return n
        }
    }

    private func store(_ provider: NamesProvider) throws -> CompanionStore {
        var s = CompanionState()
        s.dexUnlocked[4] = DexUnlock(baseID: 4, rarity: .rare, names: ["en": "Charmander"], isShiny: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("csn-\(UUID().uuidString).json")
        try JSONEncoder().encode(s).write(to: url)
        return CompanionStore(provider: provider, clock: { Date() }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testOwnedSpeciesUseTheSavedNameWithoutANetworkCall() async throws {
        let provider = NamesProvider([:])
        let s = try store(provider)
        let name = await s.catalogSpeciesName(4)
        XCTAssertEqual(name, "Charmander")
        XCTAssertTrue(provider.requested.isEmpty)
    }

    func testUnmetSpeciesAreNamedFromPokeAPI() async throws {
        let provider = NamesProvider([149: ["en": "Dragonite", "ko": "망나뇽"]])
        let s = try store(provider)
        let name = await s.catalogSpeciesName(149)
        XCTAssertEqual(name, "Dragonite")
        XCTAssertEqual(provider.requested, [149])
    }

    func testOfflineFallsBackToTheDexNumber() async throws {
        let s = try store(NamesProvider([:]))
        let name = await s.catalogSpeciesName(150)
        XCTAssertEqual(name, "#150")
    }
}
