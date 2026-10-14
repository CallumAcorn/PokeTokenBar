import Foundation

/// Competitive grade, best (S) to worst (F). Mapped from Smogon's Black/White singles tiers
/// (Uber → S … NFE/LC → F) by `scripts/competitive-data/generate.mjs`, then lowered where the app
/// can't reproduce the rated set (see `CompetitiveEntry.Adjustment`).
enum CompetitiveTier: String, Codable, Sendable, CaseIterable, Comparable {
    case s = "S", a = "A", b = "B", c = "C", d = "D", e = "E", f = "F"

    /// `<` means *better*: S < A < … < F, so `min()` picks the best tier.
    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// What a species' suggested build does in battle, read off its four moves.
enum BattleRole: String, Codable, Sendable {
    case attacker, setup, support
}

/// Which attacking stat the suggested build leans on.
enum BattleCategory: String, Codable, Sendable {
    case physical, special, mixed, status
}

/// One species' row from `Resources/competitive-gen5.json`.
///
/// Bundled rather than fetched: PokéAPI has no competitive data, and fetching it live would add new
/// third-party hosts. It also carries localized names and capture rates for every species #1–649, so
/// the dex can list species the player hasn't met yet without a network round trip per cell.
struct CompetitiveEntry: Decodable, Sendable, Identifiable {
    let id: Int
    /// PokéAPI language code → name, same shape `AppLanguage.resolveName` reads.
    let names: [String: String]
    let captureRate: Int
    let legendary: Bool
    let mythical: Bool
    /// First species of this evolution line — rarity is a property of the line, decided by its base.
    let baseID: Int
    let types: [PokemonType]
    /// Smogon's own Gen 5 tier code ("OU", "UUBL", "NFE", …), shown next to the letter grade.
    let smogonTier: String
    let tier: CompetitiveTier
    let adjusted: Adjustment?
    let role: BattleRole
    let category: BattleCategory
    let build: Build
    let source: Source

    /// Why `tier` is lower than Smogon's rating: the rated set uses moves the app can't teach
    /// (egg/tutor/event), or is built around a held item the app doesn't have.
    struct Adjustment: Decodable, Sendable {
        enum Reason: String, Decodable, Sendable { case moves, item }
        let from: CompetitiveTier
        let reasons: [Reason]
        /// PokéAPI move ids the rated set needed but this species can't learn in-app.
        let lostMoves: [Int]?
    }

    /// Suggested set — every move is learnable in-app (Gen 5 level-up, TM, egg or tutor, or a Gen 3–4 move).
    struct Build: Decodable, Sendable {
        /// PokéAPI ability slug, resolved to a display name via `CompanionStore.abilityName`.
        let ability: String
        let nature: PokemonNature
        let evs: StatSpread
        /// PokéAPI move ids.
        let moves: [Int]
    }

    struct Source: Decodable, Sendable {
        enum Kind: String, Decodable, Sendable { case smogon, auto }
        let kind: Kind
        /// Smogon format the set came from ("ou", "ubers", …) — nil for an automatic build.
        let format: String?
        /// Smogon's set name ("Swords Dance", …) — nil for an automatic build.
        let set: String?
    }

    func name(_ language: AppLanguage) -> String {
        language.resolveName(names) ?? "#\(id)"
    }
}

/// The bundled competitive catalog plus the questions the dex asks of it.
struct CompetitiveDex: Sendable {
    let entries: [Int: CompetitiveEntry]

    /// Loaded once from the app bundle. A missing or corrupt resource leaves the catalog empty rather
    /// than crashing — the dex then simply shows no competitive section.
    static let shared: CompetitiveDex = {
        guard let url = Bundle.module.url(forResource: "competitive-gen5", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dex = try? CompetitiveDex(json: data) else { return CompetitiveDex(entries: [:]) }
        return dex
    }()

    init(entries: [Int: CompetitiveEntry]) { self.entries = entries }

    init(json: Data) throws {
        struct File: Decodable { let species: [CompetitiveEntry] }
        let file = try JSONDecoder().decode(File.self, from: json)
        entries = Dictionary(file.species.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every species in Dex order.
    var all: [CompetitiveEntry] { entries.values.sorted { $0.id < $1.id } }

    /// The rarity a species hatches as — the same `Rarity.from` rule hatching uses, applied to the
    /// line's base. Lets the dex filter species the player has never met.
    func rarity(of id: Int) -> Rarity? {
        guard let entry = entries[id], let base = entries[entry.baseID] else { return nil }
        return Rarity.from(captureRate: base.captureRate, isLegendary: base.legendary, isMythical: base.mythical)
    }

    /// Best tier anywhere in the line, and the species that holds it (lowest Dex number on a tie).
    func linePeak(of id: Int) -> CompetitiveEntry? {
        guard let entry = entries[id] else { return nil }
        return entries.values.filter { $0.baseID == entry.baseID }
            .min { ($0.tier, $0.id) < ($1.tier, $1.id) }
    }

    /// Up to `limit` higher-tier species that could do this one's job.
    ///
    /// An unevolved species is judged as what its line becomes: Charmander is compared using
    /// Charizard's tier, types, role and lean, so both get the same list. Candidates must be rated
    /// above that, share a type with it, and sit outside the line. Ranked by sharing its main (first)
    /// type, then the same physical/special lean, then the same role, then tier.
    // ponytail: role/lean come from a 4-move heuristic, so this is a shortlist to compare, not a verdict.
    func alternatives(to id: Int, limit: Int = 10) -> [CompetitiveEntry] {
        guard let entry = entries[id] else { return [] }
        let peak = linePeak(of: id) ?? entry
        let me = peak.tier < entry.tier ? peak : entry
        guard let mainType = me.types.first else { return [] }
        let bar = me.tier
        func score(_ other: CompetitiveEntry) -> Int {
            (other.types.contains(mainType) ? 4 : 0)
                + (other.category == me.category ? 2 : 0)
                + (other.role == me.role ? 1 : 0)
        }
        return entries.values
            .filter { $0.baseID != me.baseID && $0.tier < bar && $0.types.contains(where: me.types.contains) }
            .map { ($0, score($0)) }
            .sorted { ($1.1, $0.0.tier, $0.0.id) < ($0.1, $1.0.tier, $1.0.id) }
            .prefix(limit)
            .map(\.0)
    }
}
