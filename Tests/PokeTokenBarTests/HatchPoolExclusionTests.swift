import XCTest
@testable import PokeTokenBar

/// Cover for `PokemonOdds.excludedFromHatchPool`.
///
/// Both tests are network-free by construction: `baseSpecies(id:)` consults the exclusion set
/// before it issues any request, so an excluded id returns nil without touching PokéAPI. A test
/// here that started hitting the network would mean the guard had moved below the fetch.
final class HatchPoolExclusionTests: XCTestCase {

    /// Trubbish (#568) must not be offered as a hatch candidate on the REST fallback path.
    ///
    /// The GraphQL base index and this fallback are separate code paths reading the same set.
    /// Excluding a species from only the GraphQL query would leave it reachable whenever
    /// GraphQL is down — a hole that shows up rarely and looks like a random hatch, not a bug.
    func testTrubbishExcludedFromRestFallback() async throws {
        let result = try await PokeAPIClient().baseSpecies(id: PokemonOdds.trubbishSpeciesID)
        XCTAssertNil(result, "Trubbish is excluded from the hatch pool")
    }

    /// Ditto must survive the generalisation from a single `_neq` to a set.
    ///
    /// Its exclusion is load-bearing rather than cosmetic: Ditto is meant to arrive only via
    /// the disguise reveal in `CompanionStore.revealDitto()`. Dropping it from the set would
    /// let it hatch normally and quietly break that mechanic.
    func testDittoRemainsExcludedAlongsideTrubbish() {
        XCTAssertTrue(PokemonOdds.excludedFromHatchPool.contains(PokemonOdds.dittoSpeciesID),
                      "Ditto lost its hatch-pool exclusion — it would now hatch as an ordinary companion")
        XCTAssertTrue(PokemonOdds.excludedFromHatchPool.contains(PokemonOdds.trubbishSpeciesID))
    }
}
