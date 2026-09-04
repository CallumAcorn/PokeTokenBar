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
}
