import Foundation

// MARK: Day Care — design: docs/specs/2026-10-21-day-care.md
//
// Everything here is pure (no store, no network) so the rules are testable on their own.
// CompanionStore owns the state changes: drop-off, incubation progress, cancel/discard, and handing a
// ready egg to the active slot.

/// A Pokémon's gender. Rolled at hatch from the species' `gender_rate`; mons hatched before the Day Care
/// existed have none saved and use `MonState.effectiveGender(genderRate:)` instead.
enum Gender: String, Codable, Sendable, Equatable {
    case male, female, genderless

    /// `genderRate` is PokéAPI's `gender_rate`: -1 genderless, otherwise the female chance in eighths
    /// (0 = always male, 8 = always female).
    static func roll(genderRate: Int, roll: UInt64) -> Gender {
        guard genderRate >= 0 else { return .genderless }
        return Int(roll % 8) < genderRate ? .female : .male
    }
}

/// The egg fields of `pokemon-species` — egg groups, gender ratio and egg cycles.
struct EggInfo: Sendable, Codable, Equatable {
    /// PokéAPI egg group slugs, e.g. "monster", "ditto", "no-eggs".
    let eggGroups: [String]
    let genderRate: Int
    /// nil when the response didn't carry it — the incubation scale then falls back to ×1.
    let hatchCounter: Int?

    var isDitto: Bool { eggGroups.contains(DayCare.dittoEggGroup) }
    var isUndiscovered: Bool { eggGroups.contains(DayCare.undiscoveredEggGroup) }
}

/// Day Care balance and game rules.
enum DayCare {
    /// Drop-off fee, paid from shop tokens and never refunded. Cheap on purpose — the real cost is the
    /// incubation, so cancelling a mistake costs little.
    static let fee = 50_000_000
    /// The second slot — a permanent shop purchase at the same tier as the Shiny Charm.
    static let secondSlotPrice = ShinyCharm.price
    static let maxSlots = 2
    /// No egg ever needs more usage than this (only Phione — mythical, 4B uncapped — reaches it).
    static let incubationCap = 2_000_000_000
    /// `hatch_counter` at which an egg needs its full base; lower counters scale down to `minScale`.
    static let fullScaleHatchCounter = 40
    static let minScale = 0.5
    /// IVs copied from the parents — 3 normally, 5 with a Destiny Knot attached.
    static let inheritedIVCount = 3
    static let destinyKnotInheritedIVCount = 5
    /// Chance (percent) the baby gets its own species' hidden ability when the passing parent has its
    /// hidden ability.
    static let hiddenAbilityPercent: UInt64 = 60
    /// Shiny denominators when a parent came from a trade (Masuda method). Normal hatches use
    /// `PokemonOdds.shinyDenominator` / `ShinyCharm.shinyDenominator`.
    static let masudaShinyDenominator: UInt64 = 32
    static let masudaCharmShinyDenominator: UInt64 = 24

    static let dittoEggGroup = "ditto"
    static let undiscoveredEggGroup = "no-eggs"
    /// Manaphy's eggs hatch Phione.
    static let babyOverrides: [Int: Int] = [490: 489]
    /// Mother lines whose eggs hatch either of two species at 50/50: Nidoran♀ → Nidoran♀/♂,
    /// Illumise → Illumise/Volbeat. The key is the mother's line base.
    static let genderSplitPartners: [Int: Int] = [29: 32, 314: 313]

    /// Usage the Day Care needs before the egg is ready:
    /// `FreshEgg.price(guaranteeing: rarity) × clamp(hatch_counter / 40, 0.5, 1.0)`, capped at 2B.
    static func incubationTarget(rarity: Rarity, hatchCounter: Int?) -> Int {
        let scale = hatchCounter.map { min(1.0, max(minScale, Double($0) / Double(fullScaleHatchCounter))) } ?? 1.0
        let base = Double(FreshEgg.price(guaranteeing: rarity))
        return min(incubationCap, Int((base * scale).rounded()))
    }

    /// One parent as the compatibility rules see it.
    struct Candidate: Sendable, Equatable {
        let monID: String
        let info: EggInfo
        let gender: Gender
    }

    enum Compatibility: Equatable, Sendable {
        case compatible
        case sameMon
        /// Either parent is in the Undiscovered group (legendaries, babies…).
        case undiscovered
        case bothDitto
        case noSharedEggGroup
        /// Same gender, or a genderless pair without Ditto.
        case genderMismatch
    }

    static func compatibility(_ a: Candidate, _ b: Candidate) -> Compatibility {
        guard a.monID != b.monID else { return .sameMon }
        if a.info.isUndiscovered || b.info.isUndiscovered { return .undiscovered }
        if a.info.isDitto && b.info.isDitto { return .bothDitto }
        if a.info.isDitto != b.info.isDitto { return .compatible }
        guard !Set(a.info.eggGroups).isDisjoint(with: b.info.eggGroups) else { return .noSharedEggGroup }
        let genders: Set<Gender> = [a.gender, b.gender]
        return genders == [.male, .female] ? .compatible : .genderMismatch
    }

    /// Index (0 or 1) of the parent whose line the baby belongs to and who passes on a hidden ability:
    /// the non-Ditto parent when paired with Ditto, otherwise the mother. Only meaningful for a
    /// compatible pair.
    static func motherIndex(_ a: Candidate, _ b: Candidate) -> Int {
        if a.info.isDitto { return 1 }
        if b.info.isDitto { return 0 }
        return a.gender == .female ? 0 : 1
    }

    /// The species that hatches from the mother's line. `roll` only matters for the gender-split lines.
    static func babySpecies(motherBaseID: Int, roll: UInt64) -> Int {
        if let override = babyOverrides[motherBaseID] { return override }
        if let partner = genderSplitPartners[motherBaseID], roll % 2 == 1 { return partner }
        return motherBaseID
    }

    /// The baby's ability: its own species' hidden ability `hiddenAbilityPercent`% of the time when the
    /// passing parent has its hidden ability, otherwise the normal hatch roll (`rolled`). Draws only when
    /// the parent has it, so other hatches keep their roll sequence.
    static func inheritedAbility(rolled: String?, options: [PokemonAbility], hiddenAbilityParent: Bool,
                                 draw: () -> UInt64) -> String? {
        guard hiddenAbilityParent, draw() % 100 < hiddenAbilityPercent,
              let hidden = options.first(where: \.isHidden) else { return rolled }
        return hidden.name
    }

    /// Picks which stats the baby copies and from which parent. Returns stat → parent index.
    static func inheritedStats(count: Int, draw: () -> UInt64) -> [(StatKind, Int)] {
        var pool = StatKind.allCases
        var out: [(StatKind, Int)] = []
        for _ in 0..<min(count, pool.count) {
            let stat = pool.remove(at: Int(draw() % UInt64(pool.count)))
            out.append((stat, Int(draw() % 2)))
        }
        return out
    }
}

/// What the baby inherits, copied from both parents at drop-off. The parents are locked while the egg
/// incubates, so nothing about them can change before the egg is ready.
struct InheritedTraits: Codable, Sendable, Equatable {
    var babySpeciesID: Int
    /// Both parents' real IV rolls (never hyper-trained values). Always two entries.
    var parentIVs: [StatSpread]
    var inheritedIVCount: Int
    /// The nature of the parent given an Everstone — copied to the baby instead of a rolled one.
    var everstoneNature: PokemonNature?
    /// The passing parent (mother, or the non-Ditto parent) has its species' hidden ability.
    var hiddenAbilityParent: Bool
    /// Every move either parent knows. At hatch, the baby keeps the ones that are its own egg moves.
    var parentMoves: [Int]
    /// A parent came from a trade (Masuda method).
    var masuda: Bool
}

/// One Day Care slot — a dropped-off pair and the egg they're incubating.
struct DayCareSlot: Codable, Sendable, Equatable, Identifiable {
    /// 0 is free; 1 needs the second-slot purchase.
    var slot: Int
    /// The two parents. Locked (no training, trading or items) until the egg is ready.
    var parentIDs: [String]
    var traits: InheritedTraits
    var babyRarity: Rarity
    /// Usage needed (`DayCare.incubationTarget`) and usage counted so far. Progress stops at target.
    var target: Int
    var progress = 0
    /// Items attached at drop-off — returned to the bag if the slot is cancelled.
    var usedDestinyKnot = false
    var usedEverstone = false
    /// The baby's localized names, saved at drop-off — it may be a species the player has never owned
    /// (a traded mother's line base), so the Pokédex can't name it. nil = resolve at display time.
    var babyNames: [String: String]?

    var id: Int { slot }
    var isReady: Bool { progress >= target }
    /// Parents stay locked only while the egg incubates.
    var lockedMonIDs: [String] { isReady ? [] : parentIDs }
}

/// Why a drop-off didn't happen — the Day Care screen shows the matching message.
enum DayCareDropOffResult: Equatable, Sendable {
    case droppedOff
    /// The slot is taken, not bought, or out of range.
    case slotUnavailable
    /// A parent is missing, the training Pokémon, already at the Day Care, or picked twice.
    case invalidParent
    case notEnoughTokens
    /// A Destiny Knot or Everstone was asked for but isn't in the bag.
    case missingItem
    /// Species data couldn't be loaded (offline) — nothing was charged.
    case dataUnavailable
    case incompatible(DayCare.Compatibility)
}
