import XCTest
@testable import PokeTokenBar

final class GymBadgeTests: XCTestCase {
    func testAllOpponentTypeMatchesAUniformRockTeam() {
        let opponent = [(name: "Geodude", types: [PokemonType.rock, .ground]), (name: "Onix", types: [PokemonType.rock, .ground])]
        XCTAssertTrue(GymBadge.earned(against: opponent).contains(.kantoBoulder))
    }

    func testAllOpponentTypeRejectsAMixedTypeTeam() {
        let opponent = [(name: "Geodude", types: [PokemonType.rock, .ground]), (name: "Pikachu", types: [PokemonType.electric])]
        XCTAssertFalse(GymBadge.earned(against: opponent).contains(.kantoBoulder))
    }

    func testAllOpponentTypeRejectsBelowTheMinimumRosterSize() {
        // A single Rock-type mon shouldn't award Brock's badge — real gyms run 2+ themed mons,
        // not a coincidental lone pick (see GymBadgeCriterion.allOpponentType's minRosterSize).
        let opponent = [(name: "Geodude", types: [PokemonType.rock, .ground])]
        XCTAssertFalse(GymBadge.earned(against: opponent).contains(.kantoBoulder))
    }

    func testOpponentRosterContainsAnyMatchesOnASignatureAce() {
        let opponent = [(name: "Golbat", types: [PokemonType.poison, .flying]), (name: "Gengar", types: [PokemonType.ghost, .poison])]
        XCTAssertTrue(GymBadge.earned(against: opponent).contains(.kantoEliteAgatha))
    }

    func testOpponentRosterContainsAnyIsCaseInsensitiveAndRejectsWithoutTheAce() {
        let lowercased = [(name: "gengar", types: [PokemonType.ghost, .poison])]
        XCTAssertTrue(GymBadge.earned(against: lowercased).contains(.kantoEliteAgatha))

        let withoutAce = [(name: "Golbat", types: [PokemonType.poison, .flying])]
        XCTAssertFalse(GymBadge.earned(against: withoutAce).contains(.kantoEliteAgatha))
    }

    func testEmptyRosterEarnsNothing() {
        XCTAssertTrue(GymBadge.earned(against: []).isEmpty)
    }

    func testACleanSweepCanEarnMultipleBadgesAtOnceAcrossRegions() {
        // Three Dragon-types, including two signature aces (Dragonite, Salamence) — a single
        // roster composition can plausibly clear badges from several regions at once: type badges
        // (any region's Dragon gym leader) alongside signature-mon badges that happen to overlap.
        let opponent = [(name: "Dragonite", types: [PokemonType.dragon, .flying]),
                         (name: "Dragonair", types: [PokemonType.dragon]),
                         (name: "Salamence", types: [PokemonType.dragon, .flying])]
        let earned = GymBadge.earned(against: opponent)
        XCTAssertTrue(earned.contains(.johtoChampion))    // signature: Dragonite
        XCTAssertTrue(earned.contains(.hoennEliteDrake))  // signature: Salamence
        XCTAssertTrue(earned.contains(.johtoRising))      // type: Dragon, 2+ (Clair)
        XCTAssertTrue(earned.contains(.unovaLegend))      // type: Dragon, 3+ (Drayden)
    }

    /// The badge list reuses types across regions on purpose (three Rock badges, four Electric
    /// badges, ...) and reuses real trainers' personas across regions too (Bruno, Lance) — without
    /// a tie-breaker, two badges could become literally unearnable-apart (any win that satisfies
    /// one always satisfies the other too). `GymBadgeCriterion.allOpponentType`'s `minRosterSize`
    /// steps up per reuse specifically to prevent this; this test is the permanent guard against a
    /// future badge edit reintroducing a collision.
    func testNoTwoBadgesShareTheSameCriterion() {
        let all = GymBadge.allCases
        for i in all.indices {
            for j in all.indices where j > i {
                XCTAssertNotEqual(all[i].info.criterion, all[j].info.criterion,
                                  "\(all[i]) and \(all[j]) have the identical unlock criterion")
            }
        }
    }

    /// Every badge has a non-empty title/trainer — catches a case added to the enum without a
    /// matching `info` entry (a missing switch case fails the build already, but this also guards
    /// against a copy-pasted-but-blank string slipping through).
    func testEveryBadgeHasDisplayMetadata() {
        for badge in GymBadge.allCases {
            XCTAssertFalse(badge.info.title.isEmpty, "\(badge) has no title")
            XCTAssertFalse(badge.info.trainerName.isEmpty, "\(badge) has no trainerName")
        }
    }

    // MARK: Play as a gym leader

    /// Every badge's suggested team, scored the way a real win is, earns that badge — "Play as"
    /// never offers a team that wouldn't hand it out. Off-type mons and non-signature mons in the
    /// party are left out.
    func testSuggestedRosterEarnsItsBadge() {
        let filler: [(id: Int, name: String, types: [PokemonType])] = [(100, "Magikarp", [.water]), (101, "Pikachu", [.electric])]
        for badge in GymBadge.allCases {
            var party = filler
            switch badge.info.criterion {
            case .allOpponentType(let type, _):
                party += (0..<8).map { (id: $0, name: "Mon\($0)", types: [type, .normal]) }
            case .opponentRosterContainsAny(let names):
                party.append((id: 0, name: names[0].uppercased(), types: []))
            }
            guard let roster = badge.suggestedRoster(from: party, maxCount: BattleClient.maxRosterSize) else {
                return XCTFail("\(badge) has no suggestion from a party built for it")
            }
            XCTAssertLessThanOrEqual(roster.count, BattleClient.maxRosterSize, "\(badge)")
            let team = roster.compactMap { id in party.first { $0.id == id }.map { (name: $0.name, types: $0.types) } }
            XCTAssertTrue(GymBadge.earned(against: team).contains(badge), "\(badge)'s suggested team doesn't earn it")
        }
    }

    /// One short of a type leader's team size → not offered. Roxanne needs 3 Rock.
    func testSuggestedRosterNeedsTheLeadersTeamSize() {
        let twoRock: [(id: Int, name: String, types: [PokemonType])] = [(1, "Geodude", [.rock, .ground]), (2, "Onix", [.rock, .ground])]
        XCTAssertNil(GymBadge.hoennStone.suggestedRoster(from: twoRock, maxCount: 6))
        XCTAssertEqual(GymBadge.kantoBoulder.suggestedRoster(from: twoRock, maxCount: 6), [1, 2])
        // A bigger Rock party still gives Brock exactly his 2, the first (strongest) ones.
        let fourRock = twoRock + [(3, "Graveler", [.rock, .ground]), (4, "Golem", [.rock, .ground])]
        XCTAssertEqual(GymBadge.kantoBoulder.suggestedRoster(from: fourRock, maxCount: 6), [1, 2])
        XCTAssertEqual(GymBadge.hoennStone.suggestedRoster(from: fourRock, maxCount: 6), [1, 2, 3])
        XCTAssertNil(GymBadge.kantoEliteLance.suggestedRoster(from: twoRock, maxCount: 6))
    }

    /// Two Rock mons are one short of Roxanne (3) — the nearest Rock badge — not Roark (4). A mixed
    /// team is short of nothing by size alone, and a team that already earns a badge doesn't list it.
    func testNearMissesNameTheNearestBadgePerType() {
        let twoRock: [(name: String, types: [PokemonType])] = [("Nosepass", [.rock]), ("Sudowoodo", [.rock])]
        let misses = GymBadge.nearMisses(for: twoRock)
        XCTAssertEqual(misses.map(\.badge), [.hoennStone], "Roxanne, not Roark (further) or Brock (already earned)")
        XCTAssertEqual(misses.first?.missing, 1)
        XCTAssertTrue(GymBadge.nearMisses(for: [("Geodude", [.rock]), ("Pikachu", [.electric])]).isEmpty)
        XCTAssertTrue(GymBadge.nearMisses(for: []).isEmpty)
    }
}

