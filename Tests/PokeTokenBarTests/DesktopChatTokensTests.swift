import XCTest
@testable import PokeTokenBar

final class DesktopChatTokensTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testParsesTheDesktopAppsFile() {
        let reading = DesktopChatTokens.parse(json(#"{"tokens-today":{"date":"2026-10-13","tokens":56409}}"#))
        XCTAssertEqual(reading, DesktopChatTokens.Reading(date: "2026-10-13", tokens: 56409))
    }

    /// Another app's private file is untrusted input: every malformed shape must be a clean nil, not a trap.
    func testRejectsMalformedShapes() {
        let bad = [
            "", "[]", "{}", "not json",
            #"{"tokens-today":[]}"#,
            #"{"tokens-today":{"date":"2026-10-13"}}"#,
            #"{"tokens-today":{"tokens":5}}"#,
            #"{"tokens-today":{"date":13,"tokens":5}}"#,
            #"{"tokens-today":{"date":"yesterday","tokens":5}}"#,
            #"{"tokens-today":{"date":"2026-10-13","tokens":"5"}}"#,
            #"{"tokens-today":{"date":"2026-10-13","tokens":true}}"#,
        ]
        for text in bad { XCTAssertNil(DesktopChatTokens.parse(json(text)), text) }
    }

    func testRejectsNegativeAndImplausiblyLargeCounts() {
        XCTAssertNil(DesktopChatTokens.parse(json(#"{"tokens-today":{"date":"2026-10-13","tokens":-1}}"#)))
        XCTAssertNil(DesktopChatTokens.parse(json(#"{"tokens-today":{"date":"2026-10-13","tokens":1e300}}"#)))
        XCTAssertNil(DesktopChatTokens.parse(json(#"{"tokens-today":{"date":"2026-10-13","tokens":10000000001}}"#)))
        XCTAssertNotNil(DesktopChatTokens.parse(json(#"{"tokens-today":{"date":"2026-10-13","tokens":10000000000}}"#)))
    }

    func testRefusesAnOversizedFileInsteadOfReadingItWhole() {
        let padding = String(repeating: " ", count: DesktopChatTokens.maxFileBytes)
        XCTAssertNil(DesktopChatTokens.parse(json(#"{"tokens-today":{"date":"2026-10-13","tokens":5}}"# + padding)))
    }

    func testReadIsANoOpOutsideTheBundledAppAndForMissingFiles() {
        let missing = URL(fileURLWithPath: "/nonexistent/buddy-tokens.json")
        XCTAssertNil(DesktopChatTokens.read(url: missing, requireBundledApp: false))
        XCTAssertNil(DesktopChatTokens.read(requireBundledApp: true), "the test process is not the bundled app")
    }

    // MARK: credit rules

    private func reading(_ date: String, _ tokens: Int) -> DesktopChatTokens.Reading { .init(date: date, tokens: tokens) }

    func testFirstSightSeedsWithoutCrediting() {
        XCTAssertNil(DesktopChatTokens.delta(lastDate: nil, lastTokens: nil, reading: reading("2026-10-13", 56409)))
    }

    func testSameDayCreditsTheIncrease() {
        XCTAssertEqual(DesktopChatTokens.delta(lastDate: "2026-10-13", lastTokens: 18211,
                                               reading: reading("2026-10-13", 56409)), 38198)
    }

    func testNoChangeCreditsNothing() {
        XCTAssertNil(DesktopChatTokens.delta(lastDate: "2026-10-13", lastTokens: 100, reading: reading("2026-10-13", 100)))
    }

    /// A restarted or reset counter reads lower than the cursor. That is not negative usage.
    func testADecreaseIsAResetNotNegativeUsage() {
        XCTAssertNil(DesktopChatTokens.delta(lastDate: "2026-10-13", lastTokens: 5000, reading: reading("2026-10-13", 40)))
    }

    /// The counter's own day rolled over, so its new value is entirely new usage.
    func testANewDayBucketCreditsTheWholeNewValue() {
        XCTAssertEqual(DesktopChatTokens.delta(lastDate: "2026-10-13", lastTokens: 90000,
                                               reading: reading("2026-10-14", 1200)), 1200)
    }

    // MARK: ledger state (what the display and the game both read)

    func testLedgerFirstSightShowsTodayButCreditsNothing() {
        var state = DesktopChatLedgerState()
        state.observe(reading("2026-10-13", 56_409), localDay: "2026-10-13")
        XCTAssertEqual(state.total(from: "2026-10-13", through: "2026-10-13"), 56_409)
        XCTAssertEqual(state.take(), 0, "the app was not watching, so nothing is credited to the game")
    }

    func testLedgerFirstSightOfAnotherDaysBucketShowsNothing() {
        var state = DesktopChatLedgerState()
        state.observe(reading("2026-10-12", 90_000), localDay: "2026-10-13")
        XCTAssertEqual(state.total(from: "2026-10-01", through: "2026-10-31"), 0)
    }

    func testLedgerGainsAccumulateByLocalDayAndAreTakenOnce() {
        var state = DesktopChatLedgerState()
        state.observe(reading("2026-10-13", 1_000), localDay: "2026-10-13")
        state.observe(reading("2026-10-13", 39_198), localDay: "2026-10-13")
        state.observe(reading("2026-10-13", 67_680), localDay: "2026-10-13")
        XCTAssertEqual(state.total(from: "2026-10-13", through: "2026-10-13"), 67_680)
        XCTAssertEqual(state.take(), 66_680)
        XCTAssertEqual(state.take(), 0, "a taken gain is never handed over twice")
    }

    /// The desktop app's bucket and the local calendar can disagree about midnight. Gains are filed
    /// under the local day they were *seen*, whichever bucket the counter reports.
    func testLedgerFilesGainsUnderTheLocalDayRegardlessOfTheCountersBucket() {
        var state = DesktopChatLedgerState()
        state.observe(reading("2026-10-12", 5_000), localDay: "2026-10-13")
        state.observe(reading("2026-10-12", 9_000), localDay: "2026-10-13")
        XCTAssertEqual(state.total(from: "2026-10-13", through: "2026-10-13"), 4_000)
        XCTAssertEqual(state.total(from: "2026-10-12", through: "2026-10-12"), 0)
    }

    func testLedgerResetCreditsNothingThenCountsFromTheNewBase() {
        var state = DesktopChatLedgerState()
        state.observe(reading("2026-10-13", 50_000), localDay: "2026-10-13")
        _ = state.take()
        state.observe(reading("2026-10-13", 300), localDay: "2026-10-13")
        XCTAssertEqual(state.take(), 0)
        state.observe(reading("2026-10-13", 1_300), localDay: "2026-10-13")
        XCTAssertEqual(state.take(), 1_000)
    }

    func testLedgerTotalsCoverWeekAndMonthRanges() {
        var state = DesktopChatLedgerState()
        state.days = ["2026-09-30": 10, "2026-10-01": 20, "2026-10-12": 30, "2026-10-13": 40]
        XCTAssertEqual(state.total(from: "2026-10-01", through: "2026-10-13"), 90)
        XCTAssertEqual(state.total(from: "2026-10-12", through: "2026-10-13"), 70)
    }

    func testLedgerKeepsOnlyTheMostRecentTwoMonths() {
        var state = DesktopChatLedgerState()
        for day in 1...80 { state.days[String(format: "2026-%02d-%02d", 1 + (day - 1) / 28, 1 + (day - 1) % 28)] = day }
        state.observe(reading("2026-10-13", 1), localDay: "2026-10-13")
        XCTAssertLessThanOrEqual(state.days.count, 62)
        XCTAssertNotNil(state.days["2026-10-13"])
    }

    func testPersistedLedgerSurvivesARestart() {
        let suite = UserDefaults(suiteName: "chat-ledger-\(UUID().uuidString)")!
        let first = DesktopChatLedger(defaults: suite)
        first.observe(reading("2026-10-13", 1_000), localDay: "2026-10-13")
        first.observe(reading("2026-10-13", 4_000), localDay: "2026-10-13")
        let second = DesktopChatLedger(defaults: suite)
        XCTAssertEqual(second.total(from: "2026-10-13", through: "2026-10-13"), 4_000)
        XCTAssertEqual(second.takeUncredited(), 3_000)
        XCTAssertEqual(DesktopChatLedger(defaults: suite).takeUncredited(), 0)
    }

    // MARK: provider

    func testProviderIsSilentUnlessTheOptInIsOn() async throws {
        UserDefaults.standard.set(false, forKey: ExternalUsageCredit.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: ExternalUsageCredit.defaultsKey) }
        let ledger = DesktopChatLedger(defaults: UserDefaults(suiteName: "chat-ledger-\(UUID().uuidString)")!)
        let provider = LocalDesktopChatProvider(ledger: ledger, reader: { DesktopChatTokens.Reading(date: "2026-10-13", tokens: 50_000) })
        let daily = try await provider.fetchDaily()
        XCTAssertNil(daily)
        let enrichment = await provider.fetchEnrichment()
        XCTAssertFalse(enrichment.periodsOK)
    }

    func testProviderReportsTodayWeekAndMonthFromTheLedger() async throws {
        UserDefaults.standard.set(true, forKey: ExternalUsageCredit.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: ExternalUsageCredit.defaultsKey) }
        let today = LocalUsageReader.todayKey()
        let ledger = DesktopChatLedger(defaults: UserDefaults(suiteName: "chat-ledger-\(UUID().uuidString)")!)
        let provider = LocalDesktopChatProvider(ledger: ledger, reader: { DesktopChatTokens.Reading(date: today, tokens: 50_000) })
        let daily = try await provider.fetchDaily()
        XCTAssertEqual(daily?.totalTokens, 50_000)
        XCTAssertEqual(daily?.date, today)
        XCTAssertEqual(daily?.totalCost, 0)
        XCTAssertEqual(provider.reportsCost, false)
        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.periodsOK)
        XCTAssertEqual(enrichment.weekTotal?.totalTokens, 50_000)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 50_000)
        XCTAssertNil(enrichment.activeBlock)
    }

    func testProviderReportsNothingBeforeAnyChatIsSeen() async throws {
        UserDefaults.standard.set(true, forKey: ExternalUsageCredit.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: ExternalUsageCredit.defaultsKey) }
        let ledger = DesktopChatLedger(defaults: UserDefaults(suiteName: "chat-ledger-\(UUID().uuidString)")!)
        let provider = LocalDesktopChatProvider(ledger: ledger, reader: { nil })
        let daily = try await provider.fetchDaily()
        XCTAssertNil(daily)
    }

    /// The ledger comes back from UserDefaults, outside the app's control. Values near Int.max would
    /// trap the next `+=`, and being saved would trap again on every launch.
    func testATamperedLedgerLoadsClamped() throws {
        let suite = UserDefaults(suiteName: "chat-ledger-\(UUID().uuidString)")!
        var evil = DesktopChatLedgerState()
        evil.cursorDate = "2026-10-14"
        evil.cursorTokens = Int.max
        evil.days = ["2026-10-14": Int.max, "2026-10-13": -5]
        evil.uncredited = Int.max
        suite.set(try JSONEncoder().encode(evil), forKey: "desktopChatLedger")

        let ledger = DesktopChatLedger(defaults: suite)
        let cap = DesktopChatTokens.maxPlausibleTokens
        XCTAssertEqual(ledger.takeUncredited(), cap)
        XCTAssertEqual(ledger.total(from: "2026-10-13", through: "2026-10-13"), 0, "negative clamps to zero")
        ledger.observe(.init(date: "2026-10-14", tokens: cap), localDay: "2026-10-14")   // no trap
        XCTAssertEqual(ledger.total(from: "2026-10-14", through: "2026-10-14"), cap)
    }

    /// Opted out means the desktop app's file is not read at all, not read and ignored.
    func testMeasuringNeverReadsTheFileWhenOptedOut() {
        var reads = 0
        let reading = DesktopChatTokens.Reading(date: "2026-10-14", tokens: 5)
        XCTAssertFalse(DesktopChatTokens.isMeasuring(enabled: false, read: { reads += 1; return reading }))
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(DesktopChatTokens.isMeasuring(enabled: true, read: { reads += 1; return reading },
                                                    now: Self.noonOn("2026-10-14")))
        XCTAssertEqual(reads, 1)
    }

    /// Observed on a real machine: desktop 2.37337 stopped writing the counter, leaving it dated
    /// 2026-07-31. Treating that as measuring switched the five-hour estimate off with nothing
    /// counting chat in its place.
    func testAStaleCounterIsNotMeasuring() {
        let stale = DesktopChatTokens.Reading(date: "2026-07-31", tokens: 9_561)
        XCTAssertFalse(DesktopChatTokens.isMeasuring(enabled: true, read: { stale }, now: Self.noonOn("2026-10-14")))
    }

    /// Today and yesterday both count, since the counter may roll over at UTC rather than local midnight.
    func testTodayAndYesterdayAreCurrent() {
        let now = Self.noonOn("2026-10-14")
        for day in ["2026-10-14", "2026-10-13"] {
            XCTAssertTrue(DesktopChatTokens.isCurrent(.init(date: day, tokens: 1), now: now), day)
        }
        XCTAssertFalse(DesktopChatTokens.isCurrent(.init(date: "2026-10-12", tokens: 1), now: now))
    }

    private static func noonOn(_ day: String) -> Date {
        let f = LocalUsageReader.localDayFormatter()
        return f.date(from: day)!.addingTimeInterval(12 * 3600)
    }
}
