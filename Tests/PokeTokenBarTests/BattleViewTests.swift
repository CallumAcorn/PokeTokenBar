import XCTest
@testable import PokeTokenBar

private extension Array where Element == BattleView.LogBeat {
    var moves: [BattleView.MoveLogEvent] { compactMap { if case .move(let e) = $0 { e } else { nil } } }
    var chips: [BattleView.EffectChip] { compactMap { if case .chip(let c) = $0 { c } else { nil } } }
}

/// [Regression] Status moves (Growl, Tail Whip, String Shot…) never move an HP bar, so without this
/// parsing there was no feedback at all when one landed — reported as "some moves aren't working"
/// when the server was actually applying them correctly (verified live via curl against the real
/// server: both Growl and Tail Whip resolved and applied their stat drops). parseLogBeats is what
/// turns the raw @pkmn/sim log into that missing confirmation text and the per-side hit effect.
@MainActor
final class BattleViewMoveLogParsingTests: XCTestCase {
    private let ash = "Ash"
    private let l = L(.en)
    // My own mon (Ash-0) using Growl on the opponent (Gary-0).
    private let growlLine = "|move|p1a: Ash-0|Growl|p2a: Gary-0"
    // The opponent's mon using Tackle on mine.
    private let tackleLine = "|move|p2a: Gary-0|Tackle|p1a: Ash-0"

    private func beats(_ log: [String], previouslySeenCount: Int = 0) -> (beats: [BattleView.LogBeat], seenCount: Int) {
        var fractions: [String: Double] = [:]
        return BattleView.parseLogBeats(from: log, previouslySeenCount: previouslySeenCount, myDisplayName: ash,
                                         l: l, hpFractions: &fractions)
    }

    func testExtractsMoveNameFromANewLogLine() {
        let result = beats([growlLine])
        XCTAssertEqual(result.beats.moves.map(\.moveName), ["Growl"])
        XCTAssertEqual(result.seenCount, 1)
    }

    func testResolvesWhichSideUsedAndWhichSideWasTargeted() {
        let result = beats([growlLine, tackleLine])
        XCTAssertEqual(result.beats.moves.count, 2)
        XCTAssertEqual(result.beats.moves[0], BattleView.MoveLogEvent(moveName: "Growl", userIsMine: true, targetIsMine: false),
                       "my mon used Growl on the opponent")
        XCTAssertEqual(result.beats.moves[1], BattleView.MoveLogEvent(moveName: "Tackle", userIsMine: false, targetIsMine: true),
                       "the opponent's mon used Tackle on mine")
    }

    /// Some self-targeting moves (Swords Dance, Growth…) omit the target field entirely — must not
    /// crash on a missing index 4, and must fall back to "landed on whoever used it".
    func testMoveWithNoExplicitTargetFallsBackToTheUser() {
        let selfBuff = "|move|p1a: Ash-0|Swords Dance|p1a: Ash-0"
        let noTargetField = "|move|p1a: Ash-0|Swords Dance"
        for line in [selfBuff, noTargetField] {
            let result = beats([line])
            XCTAssertEqual(result.beats.moves.first?.userIsMine, true)
            XCTAssertEqual(result.beats.moves.first?.targetIsMine, true, "line: \(line)")
        }
    }

    func testOnlyReturnsLinesPastPreviouslySeenCount() {
        let log = [growlLine, "|upkeep", tackleLine]
        let result = beats(log, previouslySeenCount: 1)
        XCTAssertEqual(result.beats.moves.map(\.moveName), ["Tackle"], "the already-seen Growl line must not resurface")
        XCTAssertEqual(result.seenCount, 3)
    }

    func testIgnoresNonMoveLogLines() {
        let log = ["|turn|1", "|upkeep", growlLine]
        let result = beats(log)
        XCTAssertEqual(result.beats.moves.map(\.moveName), ["Growl"])
    }

    func testNoNewLinesReturnsEmpty() {
        let result = beats([growlLine], previouslySeenCount: 1)
        XCTAssertEqual(result.beats, [])
        XCTAssertEqual(result.seenCount, 1, "seenCount must not regress when there's nothing new")
    }

    /// A shorter log than what was previously seen means a new battle replaced the old one in the
    /// same reused window (BattleWindowController never recreates it) — must reset instead of
    /// crashing on `log[negativeIndex...]`.
    func testShorterLogThanPreviouslySeenResetsRatherThanCrashing() {
        let result = beats([growlLine], previouslySeenCount: 50)
        XCTAssertEqual(result.beats.moves.map(\.moveName), ["Growl"])
        XCTAssertEqual(result.seenCount, 1)
    }

    /// [Regression] Moves used to fire their flash/banner as soon as their `Task` happened to
    /// schedule, independent of every other move or effect in the same batch — two moves in one
    /// turn (loser goes second) could visually land at the same time, or even out of order, even
    /// though `@pkmn/sim` had already resolved a strict speed/priority order for them server-side.
    /// The fix is that `parseLogBeats` preserves the log's own line order in a single interleaved
    /// list — playback (BattleView.drainBeats) just has to not reorder or parallelize it.
    func testMovesAndChipsInterleaveInTheLogsOwnOrderNotGroupedBySide() {
        // Turn: Ash-0 (faster) hits first and lowers Gary-0's attack; Gary-0 retaliates and gets
        // poisoned by a contact ability. Order matters: this is the server's own speed resolution.
        let log = [
            growlLine,
            "|-unboost|p2a: Gary-0|atk|1",
            tackleLine,
            "|-status|p1a: Ash-0|psn",
        ]
        let result = beats(log)
        // The interleaving itself is the assertion — moves/chips grouped separately (old behavior)
        // would lose this order entirely.
        let kinds = result.beats.map { beat -> String in
            switch beat {
            case .move(let e): return "move:\(e.moveName)"
            case .chip(let c): return "chip:\(c.text)"
            }
        }
        XCTAssertEqual(kinds, ["move:Growl", "chip:-1 Atk", "move:Tackle", "chip:Poisoned!"])
    }
}

/// [Regression] Only the move name + a generic flash landed on screen when a move actually did
/// something specific (a stat drop, a status, a Leech Seed drain) — reported as "not all moves show
/// an effect" / "show +X HP or whatever, +X speed for others". parseLogBeats turns the same raw
/// @pkmn/sim log into that missing numeric/named detail — some of what it reads (Leech Seed's own
/// drain) has no `|move|` line at all, only an end-of-turn tick.
@MainActor
final class BattleViewEffectChipParsingTests: XCTestCase {
    private let ash = "Ash"
    private let l = L(.en)

    private func chips(_ log: [String], previouslySeenCount: Int = 0,
                        hpFractions: inout [String: Double]) -> [BattleView.EffectChip] {
        BattleView.parseLogBeats(from: log, previouslySeenCount: previouslySeenCount, myDisplayName: ash,
                                  l: l, hpFractions: &hpFractions).beats.chips
    }

    func testBoostAndUnboostBecomeSignedStatChips() {
        var fractions: [String: Double] = [:]
        let log = ["|-boost|p1a: Ash-0|spe|1", "|-unboost|p2a: Gary-0|atk|2"]
        XCTAssertEqual(chips(log, hpFractions: &fractions), [
            BattleView.EffectChip(text: "+1 Spe", isMine: true, isPositive: true),
            BattleView.EffectChip(text: "-2 Atk", isMine: false, isPositive: false),
        ])
    }

    func testStatusLineBecomesANamedChip() {
        var fractions: [String: Double] = [:]
        XCTAssertEqual(chips(["|-status|p2a: Gary-0|brn"], hpFractions: &fractions),
                       [BattleView.EffectChip(text: "Burned!", isMine: false, isPositive: false)])
    }

    /// The first hit a mon ever takes has no prior fraction to diff against — assumes 1.0 (full HP),
    /// true for any mon that hasn't been hit yet this battle.
    func testFirstDamageLineForAnIdentityDiffsAgainstAnAssumedFullHP() {
        var fractions: [String: Double] = [:]
        XCTAssertEqual(chips(["|-damage|p2a: Gary-0|80/100"], hpFractions: &fractions),
                       [BattleView.EffectChip(text: "-20% HP", isMine: false, isPositive: false)])
        XCTAssertEqual(fractions["p2a: Gary-0"], 0.8)
    }

    /// [Regression] HP chips showed "% HP" for both sides — reported as "use actual numbers where
    /// possible". battleScene upgrades `isMine` chips to a real point count using this raw fraction
    /// (Equatable deliberately ignores it, same as `id` — see EffectChip's doc comment — so it has to
    /// be read directly, not via `==`). Never set for a non-HP chip kind — nothing to upgrade there.
    func testHPChipsCarryTheRawUnroundedFractionDeltaButOtherChipKindsDoNot() {
        var fractions: [String: Double] = [:]
        let log = ["|-damage|p2a: Gary-0|83/100", "|-boost|p1a: Ash-0|spe|1"]
        let result = chips(log, hpFractions: &fractions)
        XCTAssertEqual(result[0].hpDeltaFraction ?? .nan, -0.17, accuracy: 0.0001)
        XCTAssertNil(result[1].hpDeltaFraction)
    }

    /// Leech Seed's drain: damage to the seeded side, a heal to the other — both in one batch, with
    /// no `|move|` line anywhere near them (it fires at upkeep, not on use).
    func testLeechSeedStyleDamageAndHealInTheSameBatchBothProduceChips() {
        var fractions: [String: Double] = ["p1a: Ash-0": 1.0, "p2a: Gary-0": 0.9]
        let log = ["|-damage|p1a: Ash-0|88/100", "|-heal|p2a: Gary-0|100/100"]
        XCTAssertEqual(chips(log, hpFractions: &fractions), [
            BattleView.EffectChip(text: "-12% HP", isMine: true, isPositive: false),
            BattleView.EffectChip(text: "+10% HP", isMine: false, isPositive: true),
        ])
    }

    /// A second successive damage/heal line for the same identity diffs against the *previous* line's
    /// result, not the original 1.0 baseline — otherwise every chip after the first double-counts.
    func testSuccessiveLinesForTheSameIdentityDiffAgainstTheLastSeenFractionNotTheOriginalBaseline() {
        var fractions: [String: Double] = [:]
        let log = ["|-damage|p2a: Gary-0|80/100", "|-damage|p2a: Gary-0|65/100"]
        XCTAssertEqual(chips(log, hpFractions: &fractions).map(\.text), ["-20% HP", "-15% HP"])
    }

    func testZeroPercentDeltaProducesNoChip() {
        var fractions: [String: Double] = ["p2a: Gary-0": 1.0]
        XCTAssertEqual(chips(["|-heal|p2a: Gary-0|100/100"], hpFractions: &fractions), [])
    }

    func testFaintLineBecomesAChip() {
        var fractions: [String: Double] = [:]
        XCTAssertEqual(chips(["|faint|p2a: Gary-0"], hpFractions: &fractions),
                       [BattleView.EffectChip(text: "Fainted!", isMine: false, isPositive: false)])
    }

    func testIgnoresLinesItDoesNotUnderstand() {
        var fractions: [String: Double] = [:]
        XCTAssertEqual(chips(["|turn|3"], hpFractions: &fractions), [])
    }

    /// Same reset shape as the move-parsing equivalent test — a shorter log means a new battle reused
    /// this window. Fractions must reset too, or a new battle's mons (which can reuse the same
    /// "{displayName}-{index}" nicknames) would diff against the previous battle's stale HP.
    func testShorterLogResetsFractionsInsteadOfCorruptingDeltas() {
        var fractions: [String: Double] = ["p2a: Gary-0": 0.2]   // stale, from a previous "battle"
        XCTAssertEqual(chips(["|-damage|p2a: Gary-0|80/100"], previouslySeenCount: 50, hpFractions: &fractions),
                       [BattleView.EffectChip(text: "-20% HP", isMine: false, isPositive: false)],
                       "should diff against a fresh 1.0 baseline, not the stale 0.2")
    }
}
