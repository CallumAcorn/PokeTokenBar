import XCTest
@testable import PokeTokenBar

/// [Regression] Status moves (Growl, Tail Whip, String Shot…) never move an HP bar, so without this
/// parsing there was no feedback at all when one landed — reported as "some moves aren't working"
/// when the server was actually applying them correctly (verified live via curl against the real
/// server: both Growl and Tail Whip resolved and applied their stat drops). extractNewMoveNames is
/// what turns the raw @pkmn/sim log into that missing confirmation text.
@MainActor
final class BattleViewMoveLogParsingTests: XCTestCase {
    private let growlLine = "|move|p1a: Ash-0|Growl|p2a: Gary-0"
    private let tackleLine = "|move|p2a: Gary-0|Tackle|p1a: Ash-0"

    func testExtractsMoveNameFromANewLogLine() {
        let result = BattleView.extractNewMoveNames(from: [growlLine], previouslySeenCount: 0)
        XCTAssertEqual(result.moveNames, ["Growl"])
        XCTAssertEqual(result.seenCount, 1)
    }

    func testOnlyReturnsLinesPastPreviouslySeenCount() {
        let log = [growlLine, "|upkeep", tackleLine]
        let result = BattleView.extractNewMoveNames(from: log, previouslySeenCount: 1)
        XCTAssertEqual(result.moveNames, ["Tackle"], "the already-seen Growl line must not resurface")
        XCTAssertEqual(result.seenCount, 3)
    }

    func testIgnoresNonMoveLogLines() {
        let log = ["|turn|1", "|-unboost|p2a: Gary-0|atk|1", growlLine]
        let result = BattleView.extractNewMoveNames(from: log, previouslySeenCount: 0)
        XCTAssertEqual(result.moveNames, ["Growl"])
    }

    func testNoNewLinesReturnsEmpty() {
        let result = BattleView.extractNewMoveNames(from: [growlLine], previouslySeenCount: 1)
        XCTAssertEqual(result.moveNames, [])
        XCTAssertEqual(result.seenCount, 1, "seenCount must not regress when there's nothing new")
    }

    /// A shorter log than what was previously seen means a new battle replaced the old one in the
    /// same reused window (BattleWindowController never recreates it) — must reset instead of
    /// crashing on `log[negativeIndex...]`.
    func testShorterLogThanPreviouslySeenResetsRatherThanCrashing() {
        let result = BattleView.extractNewMoveNames(from: [growlLine], previouslySeenCount: 50)
        XCTAssertEqual(result.moveNames, ["Growl"])
        XCTAssertEqual(result.seenCount, 1)
    }
}
