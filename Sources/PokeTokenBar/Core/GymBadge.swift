import Foundation

/// A gen 1–5 gym badge / Elite Four / Champion title, earned by winning a battle whose opponent's
/// *revealed* roster (team preview — every mon in `you`/`opponent`'s team, not just the ones
/// actually sent out; see `BattleClient.opponentRosterNames`) matches that trainer's real in-game
/// team. Two matching shapes, mirroring how the actual games differ:
///
/// - Regular gym leaders run a single-type team → `.allOpponentType`.
/// - Elite Four/Champions mix types, so they're matched on their most iconic ace(s) instead →
///   `.opponentRosterContainsAny`. Real E4/champion teams vary by version (remakes, sequels); each
///   list here picks the mon(s) most commonly associated with that trainer, not a literal replica
///   of one specific game's team — a deliberate approximation for a cosmetic feature, not a claim
///   of frame-perfect canonicity.
///
/// No opponent ever "declares" they're playing a gym leader — a badge is just pattern-matched
/// after the fact off whatever roster they actually brought, same honor-system spirit as
/// everything else self-reported in a battle (see battles.md's Trust model section).
enum GymBadge: String, Codable, CaseIterable, Sendable, Hashable {
    // Kanto — Red/Blue/Yellow, FireRed/LeafGreen
    case kantoBoulder, kantoCascade, kantoThunder, kantoRainbow, kantoSoul, kantoMarsh, kantoVolcano, kantoEarth
    case kantoEliteLorelei, kantoEliteBruno, kantoEliteAgatha, kantoEliteLance, kantoChampion

    // Johto — Gold/Silver/Crystal
    case johtoZephyr, johtoHive, johtoPlain, johtoFog, johtoStorm, johtoMineral, johtoGlacier, johtoRising
    case johtoEliteWill, johtoEliteKoga, johtoEliteBruno, johtoEliteKaren, johtoChampion

    // Hoenn — Ruby/Sapphire/Emerald
    case hoennStone, hoennKnuckle, hoennDynamo, hoennHeat, hoennBalance, hoennFeather, hoennMind, hoennRain
    case hoennEliteSidney, hoennElitePhoebe, hoennEliteGlacia, hoennEliteDrake, hoennChampion

    // Sinnoh — Diamond/Pearl/Platinum
    case sinnohCoal, sinnohForest, sinnohCobble, sinnohFen, sinnohRelic, sinnohMine, sinnohIcicle, sinnohBeacon
    case sinnohEliteAaron, sinnohEliteBertha, sinnohEliteFlint, sinnohEliteLucian, sinnohChampion

    // Unova — Black/White
    case unovaTrio, unovaBasic, unovaInsect, unovaBolt, unovaQuake, unovaJet, unovaFreeze, unovaLegend
    case unovaEliteShauntal, unovaEliteMarshal, unovaEliteGrimsley, unovaEliteCaitlin, unovaChampion
}

/// How a win against a given opponent roster earns a badge.
enum GymBadgeCriterion: Equatable {
    /// Every mon in the opponent's revealed roster has this type, and the roster has at least
    /// `minRosterSize` mons. The same type is reused by multiple regions' gym leaders (e.g. three
    /// different Rock badges), so `minRosterSize` also does double duty as the tie-breaker that
    /// keeps every badge's criterion literally distinct — each later reuse of a type steps the
    /// minimum up by one (2, 3, 4, ...) in declaration order, checked by
    /// GymBadgeTests.testNoTwoBadgesShareTheSameCriterion. Never exceeds 6 (BattleClient's own
    /// roster cap) — 40 gym-leader badges spread across 16 types tops out at electric's 4th reuse
    /// (size 5), with headroom to spare.
    case allOpponentType(PokemonType, minRosterSize: Int = 2)
    /// The opponent's revealed roster includes at least one of these species (English display
    /// names, matched case-insensitively).
    case opponentRosterContainsAny([String])
}

struct GymBadgeInfo {
    let title: String
    let trainerName: String
    let region: String
    let criterion: GymBadgeCriterion
}

extension GymBadge {
    /// Split into five per-region dictionary literals rather than one 65-case switch — CI's
    /// `swift test --enable-code-coverage` (older Xcode 16 / Swift 6.0 toolchain, `macos-15`
    /// runner) hit a bare, fileless `error: fatalError` compiling the test target right after this
    /// file's original single-switch form landed; that shape (one huge switch expression building
    /// nested struct/enum literals, then run back through coverage instrumentation) is a known
    /// class of compiler crash on older toolchains, and this local machine's newer Swift (6.3.3)
    /// can't reproduce it to confirm — so this is a defensive split, not a verified root-cause fix.
    /// A missing entry force-unwraps rather than relying on switch exhaustiveness for the same
    /// "every case has an info" guarantee — caught immediately by
    /// `GymBadgeTests.testEveryBadgeHasDisplayMetadata`, which already iterates every case.
    var info: GymBadgeInfo {
        Self.kantoInfo[self] ?? Self.johtoInfo[self] ?? Self.hoennInfo[self] ?? Self.sinnohInfo[self] ?? Self.unovaInfo[self]!
    }

    private static let kantoInfo: [GymBadge: GymBadgeInfo] = [
        .kantoBoulder: GymBadgeInfo(title: "Boulder Badge", trainerName: "Brock", region: "Kanto", criterion: .allOpponentType(.rock)),
        .kantoCascade: GymBadgeInfo(title: "Cascade Badge", trainerName: "Misty", region: "Kanto", criterion: .allOpponentType(.water)),
        .kantoThunder: GymBadgeInfo(title: "Thunder Badge", trainerName: "Lt. Surge", region: "Kanto", criterion: .allOpponentType(.electric)),
        .kantoRainbow: GymBadgeInfo(title: "Rainbow Badge", trainerName: "Erika", region: "Kanto", criterion: .allOpponentType(.grass)),
        .kantoSoul: GymBadgeInfo(title: "Soul Badge", trainerName: "Koga", region: "Kanto", criterion: .allOpponentType(.poison)),
        .kantoMarsh: GymBadgeInfo(title: "Marsh Badge", trainerName: "Sabrina", region: "Kanto", criterion: .allOpponentType(.psychic)),
        .kantoVolcano: GymBadgeInfo(title: "Volcano Badge", trainerName: "Blaine", region: "Kanto", criterion: .allOpponentType(.fire)),
        .kantoEarth: GymBadgeInfo(title: "Earth Badge", trainerName: "Giovanni", region: "Kanto", criterion: .allOpponentType(.ground)),
        .kantoEliteLorelei: GymBadgeInfo(title: "Elite Four — Lorelei", trainerName: "Lorelei", region: "Kanto", criterion: .opponentRosterContainsAny(["Lapras"])),
        .kantoEliteBruno: GymBadgeInfo(title: "Elite Four — Bruno", trainerName: "Bruno", region: "Kanto", criterion: .opponentRosterContainsAny(["Machamp"])),
        .kantoEliteAgatha: GymBadgeInfo(title: "Elite Four — Agatha", trainerName: "Agatha", region: "Kanto", criterion: .opponentRosterContainsAny(["Gengar"])),
        .kantoEliteLance: GymBadgeInfo(title: "Elite Four — Lance", trainerName: "Lance", region: "Kanto", criterion: .opponentRosterContainsAny(["Aerodactyl"])),
        .kantoChampion: GymBadgeInfo(title: "Champion — Blue", trainerName: "Blue", region: "Kanto", criterion: .opponentRosterContainsAny(["Pidgeot", "Alakazam"])),
    ]

    private static let johtoInfo: [GymBadge: GymBadgeInfo] = [
        .johtoZephyr: GymBadgeInfo(title: "Zephyr Badge", trainerName: "Falkner", region: "Johto", criterion: .allOpponentType(.flying)),
        .johtoHive: GymBadgeInfo(title: "Hive Badge", trainerName: "Bugsy", region: "Johto", criterion: .allOpponentType(.bug)),
        .johtoPlain: GymBadgeInfo(title: "Plain Badge", trainerName: "Whitney", region: "Johto", criterion: .allOpponentType(.normal)),
        .johtoFog: GymBadgeInfo(title: "Fog Badge", trainerName: "Morty", region: "Johto", criterion: .allOpponentType(.ghost)),
        .johtoStorm: GymBadgeInfo(title: "Storm Badge", trainerName: "Chuck", region: "Johto", criterion: .allOpponentType(.fighting)),
        .johtoMineral: GymBadgeInfo(title: "Mineral Badge", trainerName: "Jasmine", region: "Johto", criterion: .allOpponentType(.steel)),
        .johtoGlacier: GymBadgeInfo(title: "Glacier Badge", trainerName: "Pryce", region: "Johto", criterion: .allOpponentType(.ice)),
        .johtoRising: GymBadgeInfo(title: "Rising Badge", trainerName: "Clair", region: "Johto", criterion: .allOpponentType(.dragon)),
        .johtoEliteWill: GymBadgeInfo(title: "Elite Four — Will", trainerName: "Will", region: "Johto", criterion: .opponentRosterContainsAny(["Xatu"])),
        .johtoEliteKoga: GymBadgeInfo(title: "Elite Four — Koga", trainerName: "Koga", region: "Johto", criterion: .opponentRosterContainsAny(["Crobat"])),
        .johtoEliteBruno: GymBadgeInfo(title: "Elite Four — Bruno", trainerName: "Bruno", region: "Johto", criterion: .opponentRosterContainsAny(["Hitmonlee"])),
        .johtoEliteKaren: GymBadgeInfo(title: "Elite Four — Karen", trainerName: "Karen", region: "Johto", criterion: .opponentRosterContainsAny(["Umbreon", "Houndoom"])),
        .johtoChampion: GymBadgeInfo(title: "Champion — Lance", trainerName: "Lance", region: "Johto", criterion: .opponentRosterContainsAny(["Dragonite"])),
    ]

    private static let hoennInfo: [GymBadge: GymBadgeInfo] = [
        .hoennStone: GymBadgeInfo(title: "Stone Badge", trainerName: "Roxanne", region: "Hoenn", criterion: .allOpponentType(.rock, minRosterSize: 3)),
        .hoennKnuckle: GymBadgeInfo(title: "Knuckle Badge", trainerName: "Brawly", region: "Hoenn", criterion: .allOpponentType(.fighting, minRosterSize: 3)),
        .hoennDynamo: GymBadgeInfo(title: "Dynamo Badge", trainerName: "Wattson", region: "Hoenn", criterion: .allOpponentType(.electric, minRosterSize: 3)),
        .hoennHeat: GymBadgeInfo(title: "Heat Badge", trainerName: "Flannery", region: "Hoenn", criterion: .allOpponentType(.fire, minRosterSize: 3)),
        .hoennBalance: GymBadgeInfo(title: "Balance Badge", trainerName: "Norman", region: "Hoenn", criterion: .allOpponentType(.normal, minRosterSize: 3)),
        .hoennFeather: GymBadgeInfo(title: "Feather Badge", trainerName: "Winona", region: "Hoenn", criterion: .allOpponentType(.flying, minRosterSize: 3)),
        .hoennMind: GymBadgeInfo(title: "Mind Badge", trainerName: "Tate & Liza", region: "Hoenn", criterion: .allOpponentType(.psychic, minRosterSize: 3)),
        .hoennRain: GymBadgeInfo(title: "Rain Badge", trainerName: "Wallace", region: "Hoenn", criterion: .allOpponentType(.water, minRosterSize: 3)),
        .hoennEliteSidney: GymBadgeInfo(title: "Elite Four — Sidney", trainerName: "Sidney", region: "Hoenn", criterion: .opponentRosterContainsAny(["Absol"])),
        .hoennElitePhoebe: GymBadgeInfo(title: "Elite Four — Phoebe", trainerName: "Phoebe", region: "Hoenn", criterion: .opponentRosterContainsAny(["Dusclops", "Banette"])),
        .hoennEliteGlacia: GymBadgeInfo(title: "Elite Four — Glacia", trainerName: "Glacia", region: "Hoenn", criterion: .opponentRosterContainsAny(["Walrein"])),
        .hoennEliteDrake: GymBadgeInfo(title: "Elite Four — Drake", trainerName: "Drake", region: "Hoenn", criterion: .opponentRosterContainsAny(["Salamence"])),
        .hoennChampion: GymBadgeInfo(title: "Champion — Steven", trainerName: "Steven Stone", region: "Hoenn", criterion: .opponentRosterContainsAny(["Metagross"])),
    ]

    private static let sinnohInfo: [GymBadge: GymBadgeInfo] = [
        .sinnohCoal: GymBadgeInfo(title: "Coal Badge", trainerName: "Roark", region: "Sinnoh", criterion: .allOpponentType(.rock, minRosterSize: 4)),
        .sinnohForest: GymBadgeInfo(title: "Forest Badge", trainerName: "Gardenia", region: "Sinnoh", criterion: .allOpponentType(.grass, minRosterSize: 3)),
        .sinnohCobble: GymBadgeInfo(title: "Cobble Badge", trainerName: "Maylene", region: "Sinnoh", criterion: .allOpponentType(.fighting, minRosterSize: 4)),
        .sinnohFen: GymBadgeInfo(title: "Fen Badge", trainerName: "Crasher Wake", region: "Sinnoh", criterion: .allOpponentType(.water, minRosterSize: 4)),
        .sinnohRelic: GymBadgeInfo(title: "Relic Badge", trainerName: "Fantina", region: "Sinnoh", criterion: .allOpponentType(.ghost, minRosterSize: 3)),
        .sinnohMine: GymBadgeInfo(title: "Mine Badge", trainerName: "Byron", region: "Sinnoh", criterion: .allOpponentType(.steel, minRosterSize: 3)),
        .sinnohIcicle: GymBadgeInfo(title: "Icicle Badge", trainerName: "Candice", region: "Sinnoh", criterion: .allOpponentType(.ice, minRosterSize: 3)),
        .sinnohBeacon: GymBadgeInfo(title: "Beacon Badge", trainerName: "Volkner", region: "Sinnoh", criterion: .allOpponentType(.electric, minRosterSize: 4)),
        .sinnohEliteAaron: GymBadgeInfo(title: "Elite Four — Aaron", trainerName: "Aaron", region: "Sinnoh", criterion: .opponentRosterContainsAny(["Drapion", "Heracross"])),
        .sinnohEliteBertha: GymBadgeInfo(title: "Elite Four — Bertha", trainerName: "Bertha", region: "Sinnoh", criterion: .opponentRosterContainsAny(["Hippowdon", "Rhyperior"])),
        .sinnohEliteFlint: GymBadgeInfo(title: "Elite Four — Flint", trainerName: "Flint", region: "Sinnoh", criterion: .opponentRosterContainsAny(["Infernape"])),
        .sinnohEliteLucian: GymBadgeInfo(title: "Elite Four — Lucian", trainerName: "Lucian", region: "Sinnoh", criterion: .opponentRosterContainsAny(["Bronzong", "Alakazam"])),
        .sinnohChampion: GymBadgeInfo(title: "Champion — Cynthia", trainerName: "Cynthia", region: "Sinnoh", criterion: .opponentRosterContainsAny(["Garchomp"])),
    ]

    private static let unovaInfo: [GymBadge: GymBadgeInfo] = [
        .unovaTrio: GymBadgeInfo(title: "Trio Badge", trainerName: "Cilan, Chili & Cress", region: "Unova",
                                  criterion: .opponentRosterContainsAny(["Pansage", "Simisage", "Pansear", "Simisear", "Panpour", "Simipour"])),
        .unovaBasic: GymBadgeInfo(title: "Basic Badge", trainerName: "Lenora", region: "Unova", criterion: .allOpponentType(.normal, minRosterSize: 4)),
        .unovaInsect: GymBadgeInfo(title: "Insect Badge", trainerName: "Burgh", region: "Unova", criterion: .allOpponentType(.bug, minRosterSize: 3)),
        .unovaBolt: GymBadgeInfo(title: "Bolt Badge", trainerName: "Elesa", region: "Unova", criterion: .allOpponentType(.electric, minRosterSize: 5)),
        .unovaQuake: GymBadgeInfo(title: "Quake Badge", trainerName: "Clay", region: "Unova", criterion: .allOpponentType(.ground, minRosterSize: 3)),
        .unovaJet: GymBadgeInfo(title: "Jet Badge", trainerName: "Skyla", region: "Unova", criterion: .allOpponentType(.flying, minRosterSize: 4)),
        .unovaFreeze: GymBadgeInfo(title: "Freeze Badge", trainerName: "Brycen", region: "Unova", criterion: .allOpponentType(.ice, minRosterSize: 4)),
        .unovaLegend: GymBadgeInfo(title: "Legend Badge", trainerName: "Drayden", region: "Unova", criterion: .allOpponentType(.dragon, minRosterSize: 3)),
        .unovaEliteShauntal: GymBadgeInfo(title: "Elite Four — Shauntal", trainerName: "Shauntal", region: "Unova", criterion: .opponentRosterContainsAny(["Chandelure"])),
        .unovaEliteMarshal: GymBadgeInfo(title: "Elite Four — Marshal", trainerName: "Marshal", region: "Unova", criterion: .opponentRosterContainsAny(["Conkeldurr"])),
        .unovaEliteGrimsley: GymBadgeInfo(title: "Elite Four — Grimsley", trainerName: "Grimsley", region: "Unova", criterion: .opponentRosterContainsAny(["Bisharp", "Scrafty"])),
        .unovaEliteCaitlin: GymBadgeInfo(title: "Elite Four — Caitlin", trainerName: "Caitlin", region: "Unova", criterion: .opponentRosterContainsAny(["Reuniclus", "Gothitelle"])),
        .unovaChampion: GymBadgeInfo(title: "Champion — Alder", trainerName: "Alder", region: "Unova", criterion: .opponentRosterContainsAny(["Volcarona"])),
    ]

    /// Index into `PokeAPI/sprites`' `sprites/badges/{n}.png` set (fetched at runtime — see
    /// `SpriteLoader.badgeImage`, same "URL, not bundled" approach the rest of this app already
    /// uses for every other sprite). That set only ever had real gym-leader art (its pre-flatten
    /// history shows exactly 8 files per generation folder, gen1–gen5) — nil for the 25 Elite
    /// Four/Champion badges, which fall back to a plain glyph.
    ///
    /// The flat numbering isn't documented anywhere in the source repo (no manifest, filenames are
    /// bare digits) — reconstructed by walking its git history back to the last commit before the
    /// gen-folders got flattened (each rename showed old path -> new number) for Kanto through
    /// Sinnoh (1–32, untouched since), then by downloading and visually matching images against
    /// real badge appearances for Unova (33–41, since renumbered by later "insert missing badges"
    /// commits — note 35 isn't Unova at all, some unrelated badge landed on that slot).
    var artworkSpriteNumber: Int? {
        switch self {
        case .kantoBoulder: return 1
        case .kantoCascade: return 2
        case .kantoThunder: return 3
        case .kantoRainbow: return 4
        case .kantoSoul: return 5
        case .kantoMarsh: return 6
        case .kantoVolcano: return 7
        case .kantoEarth: return 8
        case .johtoZephyr: return 9
        case .johtoHive: return 10
        case .johtoPlain: return 11
        case .johtoFog: return 12
        case .johtoStorm: return 13
        case .johtoMineral: return 14
        case .johtoGlacier: return 15
        case .johtoRising: return 16
        case .hoennStone: return 17
        case .hoennKnuckle: return 18
        case .hoennDynamo: return 19
        case .hoennHeat: return 20
        case .hoennBalance: return 21
        case .hoennFeather: return 22
        case .hoennMind: return 23
        case .hoennRain: return 24
        case .sinnohCoal: return 25
        case .sinnohForest: return 26
        case .sinnohCobble: return 27
        case .sinnohFen: return 28
        case .sinnohRelic: return 29
        case .sinnohMine: return 30
        case .sinnohIcicle: return 31
        case .sinnohBeacon: return 32
        case .unovaTrio: return 33
        case .unovaBasic: return 34
        case .unovaInsect: return 36
        case .unovaBolt: return 37
        case .unovaQuake: return 38
        case .unovaJet: return 39
        case .unovaFreeze: return 40
        case .unovaLegend: return 41
        default: return nil   // Elite Four / Champion — no art in the source set
        }
    }

    /// Which badges a win against this opponent roster earns. `opponent` is every mon in the
    /// revealed team-preview roster (see `BattleClient.opponentRosterNames`) paired with its
    /// types — call once per completed, won battle (see `BattleStore`).
    static func earned(against opponent: [(name: String, types: [PokemonType])]) -> Set<GymBadge> {
        guard !opponent.isEmpty else { return [] }
        var out: Set<GymBadge> = []
        for badge in GymBadge.allCases {
            switch badge.info.criterion {
            case .allOpponentType(let type, let minRosterSize):
                guard opponent.count >= minRosterSize, opponent.allSatisfy({ $0.types.contains(type) }) else { continue }
                out.insert(badge)
            case .opponentRosterContainsAny(let names):
                let wanted = Set(names.map { $0.lowercased() })
                guard opponent.contains(where: { wanted.contains($0.name.lowercased()) }) else { continue }
                out.insert(badge)
            }
        }
        return out
    }
}
