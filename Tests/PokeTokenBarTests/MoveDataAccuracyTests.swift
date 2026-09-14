import XCTest
@testable import PokeTokenBar

/// Gen 5 vs. PokeAPI move-data drift — see `PokeAPIClient.gen5MoveOverrides`'s doc comment. Real
/// network calls, same convention `DittoTests.testDittoExcludedFromRestFallback` already uses for
/// this client (no mock layer for `PokeAPIClient` itself).
final class MoveDataAccuracyTests: XCTestCase {
    /// Tackle: PokeAPI's default response is the current-game 50/100/35 already (no drift for this
    /// one anymore as of a past buff being long-settled) — picked because it exercises all three
    /// numeric fields at once and is exhaustively cross-checked against `@pkmn/sim`'s gen5 dex.
    func testTackleMatchesGen5Numbers() async throws {
        let move = try await PokeAPIClient().moveDetail(id: 33)
        XCTAssertEqual(move.power, 50)
        XCTAssertEqual(move.accuracy, 100)
        XCTAssertEqual(move.pp, 35)
    }

    /// Recover: a status move (nil power) whose PP actually changed post-Gen5 (PokéAPI's current
    /// value is 5, Gen 5's was 10) — the override must win over the live fetch, not just pass
    /// through PokéAPI's current-game number.
    func testRecoverUsesGen5PPNotPokeAPIsCurrentValue() async throws {
        let move = try await PokeAPIClient().moveDetail(id: 105)
        XCTAssertNil(move.power)
        XCTAssertEqual(move.pp, 10, "PokéAPI's own current value (5) would fail this if the override weren't applied")
    }

    /// Vise Grip — the one move (of all 458 real Gen<=5 moves) where the generic slugify doesn't
    /// match PokéAPI's slug at all ("vise-grip" vs. PokéAPI's still-old-spelling "vice-grip").
    /// Exercises the alias in `slug(fromDisplayName:)`, the battle-log name-lookup path.
    func testViseGripSlugAliasResolves() async throws {
        let move = try await PokeAPIClient().moveDetail(name: "Vise Grip")
        XCTAssertEqual(move.name, "vice-grip", "PokéAPI's actual slug for this move")
    }
}
