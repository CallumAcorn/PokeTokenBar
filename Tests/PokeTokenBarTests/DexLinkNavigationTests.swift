import XCTest
@testable import PokeTokenBar

/// A sprite link opens that species' Pokédex page from anywhere in the popover (upstream #394).
@MainActor
final class DexLinkNavigationTests: XCTestCase {
    func testOpenDexLandsOnTheCollectionWithTheSpeciesQueued() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.openDex(6)
        XCTAssertEqual(nav.tab, .collection)
        XCTAssertFalse(nav.showSettings, "a link out of Settings must not leave Settings covering it")
        XCTAssertEqual(nav.dexSpeciesLink, 6)
    }

    /// Reopening the popover starts on Home with no stale link waiting to fire.
    func testResetDropsAPendingLink() {
        let nav = PopoverNavigation()
        nav.openDex(6)
        nav.reset()
        XCTAssertNil(nav.dexSpeciesLink)
        XCTAssertEqual(nav.tab, .home)
    }
}
