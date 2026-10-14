import XCTest
@testable import PokeTokenBar

/// `PokeAPIClient.moveDescriptions` — which game's in-game text each language gets.
final class MoveDescriptionTests: XCTestCase {
    private func entry(_ text: String, _ lang: String, _ versionGroup: String) -> FlavorTextDTO {
        FlavorTextDTO(flavor_text: text, language: NamedRef(name: lang, url: nil),
                      version_group: NamedRef(name: versionGroup, url: nil))
    }

    /// PokéAPI lists entries oldest first; Black/White wins even when newer games follow it.
    func testPrefersBlackWhiteOverNewerGames() {
        let result = PokeAPIClient.moveDescriptions([
            entry("Gold text", "en", "gold-silver"),
            entry("BW text", "en", "black-white"),
            entry("Sun text", "en", "sun-moon"),
        ], langCodes: ["en"])
        XCTAssertEqual(result["en"], "BW text")
    }

    func testFallsBackToBlack2White2ThenNewest() {
        let result = PokeAPIClient.moveDescriptions([
            entry("B2W2 text", "fr", "black-2-white-2"),
            entry("Old ko", "ko", "x-y"),
            entry("New ko", "ko", "sun-moon"),
        ], langCodes: ["fr", "ko"])
        XCTAssertEqual(result["fr"], "B2W2 text")
        XCTAssertEqual(result["ko"], "New ko")
    }

    /// In-game text is hard-wrapped; a soft hyphen at a line break joins the word back together.
    func testFlattensLineBreaksAndSoftHyphens() {
        let result = PokeAPIClient.moveDescriptions([
            entry("The user lunges\nat the tar\u{AD}\nget  quickly.", "en", "black-white"),
        ], langCodes: ["en"])
        XCTAssertEqual(result["en"], "The user lunges at the target quickly.")
    }

    /// Empty, not nil: a fully fetched move with no text must not look like an unfetched summary,
    /// or `moveDetail(id:)` would refetch it on every view.
    func testNoMatchingLanguageGivesEmptyNotNil() {
        XCTAssertEqual(PokeAPIClient.moveDescriptions([entry("x", "de", "black-white")], langCodes: ["en"]), [:])
        XCTAssertEqual(PokeAPIClient.moveDescriptions([], langCodes: ["en"]), [:])
    }

    /// The app's language picks its description the same way it picks a name (pt → English).
    func testLocalizedDescriptionFollowsAppLanguage() {
        let move = Move(id: 98, name: "quick-attack", type: .normal, power: 40, accuracy: 100, pp: 30,
                        damageClass: .physical, names: ["en": "Quick Attack"],
                        descriptions: ["en": "English", "fr": "Français"], priority: 1)
        XCTAssertEqual(move.localizedDescription(.fr), "Français")
        XCTAssertEqual(move.localizedDescription(.pt), "English")
        XCTAssertNil(Move(id: 1, name: "pound", type: .normal, power: 40, accuracy: 100, pp: 35,
                          damageClass: .physical, names: [:]).localizedDescription(.en))
    }
}
