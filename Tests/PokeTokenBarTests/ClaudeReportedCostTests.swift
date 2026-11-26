import XCTest
@testable import PokeTokenBar

/// Claude Code writes its own priced ledger (`cost-state`) into each session file. It is preferred
/// over the price table, which overstated one measured session by 13% ($6.95 against $6.13).
final class ClaudeReportedCostTests: XCTestCase {
    private typealias R = LocalUsageReader

    func testParsesPerModelCostsAndStripsTheContextSuffix() throws {
        let line = #"{"type":"cost-state","modelUsage":{"claude-opus-5-5[1m]":{"costUSD":6.12},"claude-opus-5-5":{"costUSD":0.5},"claude-haiku-4-5-20251001":{"costUSD":0.002}},"hasUnknownModelCost":false}"#
        let state = try XCTUnwrap(R.parseClaudeCostStateLine(line))
        XCTAssertEqual(state.costByModel["claude-opus-5-5"] ?? 0, 6.62, accuracy: 1e-9, "both variants are one model's spend")
        XCTAssertEqual(state.costByModel["claude-haiku-4-5-20251001"] ?? 0, 0.002, accuracy: 1e-9)
    }

    /// A cost from a file is outside input: negative, non-finite or absurd values are dropped.
    func testRejectsImplausibleCosts() {
        XCTAssertNil(R.parseClaudeCostStateLine(#"{"type":"cost-state","modelUsage":{"m":{"costUSD":-1}}}"#))
        XCTAssertNil(R.parseClaudeCostStateLine(#"{"type":"cost-state","modelUsage":{"m":{"costUSD":1e12}}}"#))
        XCTAssertNil(R.parseClaudeCostStateLine(#"{"type":"assistant","modelUsage":{"m":{"costUSD":1}}}"#))
    }

    func testSpreadsTheSessionTotalExactlyAndSkipsUnparsedModels() {
        let day = "2026-10-21"
        func e(_ id: String, _ model: String, _ tokens: Int) -> R.Entry {
            R.Entry(id: id, date: Date(), localDay: day, model: model, input: tokens, output: 0, cacheWrite: 0, cacheRead: 0)
        }
        let entries = [e("a", "claude-opus-5-5", 300), e("b", "claude-opus-5-5", 100), e("c", "claude-sonnet-5", 50)]
        let state = R.ClaudeCostState(costByModel: ["claude-opus-5-5": 4.0, "claude-haiku-4-5-20251001": 9.0])
        let out = R.applyReportedCost(entries, state)
        XCTAssertEqual(out[0].explicitCost ?? 0, 3.0, accuracy: 1e-9)
        XCTAssertEqual(out[1].explicitCost ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertNil(out[2].explicitCost, "an unreported model keeps the table price")
        XCTAssertEqual(out.compactMap(\.explicitCost).reduce(0, +), 4.0, accuracy: 1e-9,
                       "a model with no parsed entry (haiku) must not inflate another model's day")
    }

    // MARK: Incremental parsing (upstream 8f74054b, #338)

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crc-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func assistant(id: String, ts: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r\#(id)","message":{"id":"m\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    private func ledger(_ cost: Double) -> String {
        #"{"type":"cost-state","modelUsage":{"claude-opus-5-5[1m]":{"costUSD":\#(cost)}}}"#
    }

    /// The cache keeps raw entries plus the latest ledger, so an appended ledger re-prices the
    /// entries parsed earlier instead of only the new tail.
    func testIncrementalAppendReattributesTheWholeSessionToLatestLedger() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let prefix = assistant(id: "a", ts: "2026-09-15T10:00:00.000Z") + "\n" + ledger(1) + "\n"
        try prefix.write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: dir.appendingPathComponent("cache.json"))
        let initial = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(initial.compactMap(\.explicitCost).reduce(0, +), 1, accuracy: 1e-9)

        try (prefix + assistant(id: "b", ts: "2026-09-16T10:00:00.000Z") + "\n" + ledger(9) + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let appended = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(appended.count, 2)
        XCTAssertTrue(appended.allSatisfy { $0.explicitCost == 4.5 })

        let unchanged = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertTrue(unchanged.allSatisfy { $0.explicitCost == 4.5 })
    }

    /// The ledger survives a reload of the persisted cache when the appended tail has none.
    func testPersistedLedgerIsRetainedWhenTheAppendedTailHasNoLedger() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let cacheURL = dir.appendingPathComponent("cache.json")
        let prefix = assistant(id: "a", ts: "2026-09-15T10:00:00.000Z") + "\n" + ledger(4) + "\n"
        try prefix.write(to: url, atomically: true, encoding: .utf8)
        _ = await LocalUsageCache(claudeRoot: dir, fileURL: cacheURL).claudeEntries(modifiedSince: .distantPast)

        try (prefix + assistant(id: "b", ts: "2026-09-16T10:00:00.000Z") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let entries = await LocalUsageCache(claudeRoot: dir, fileURL: cacheURL).claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.explicitCost == 2 })
    }

    /// A truncated file is re-read from the start, so its old ledger must not carry over.
    func testTruncationDiscardsTheCachedLedger() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let line = assistant(id: "a", ts: "2026-09-15T10:00:00.000Z")
        try (line + "\n" + ledger(9) + "\n").write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: dir.appendingPathComponent("cache.json"))
        _ = await cache.claudeEntries(modifiedSince: .distantPast)

        try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        let entries = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.explicitCost)
    }

    /// A ledger line cut mid-write is retried once it is complete.
    func testHalfWrittenCostStateIsRetriedOnAppend() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let prefix = assistant(id: "a", ts: "2026-09-15T10:00:00.000Z") + "\n"
        let full = ledger(9)
        try (prefix + full.prefix(full.count / 2)).write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: dir.appendingPathComponent("cache.json"))
        let initial = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertNil(initial.first?.explicitCost)

        try (prefix + full + "\n").write(to: url, atomically: true, encoding: .utf8)
        let completed = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.explicitCost ?? 0, 9, accuracy: 1e-9)
    }

    /// End to end: a session file's day costs what Claude reported, not the table estimate.
    func testSessionFileCostsWhatClaudeReported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString).jsonl")
        let ts = "2026-10-21T01:00:00.000Z"
        let lines = [
            #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":500000}}}"#,
            #"{"type":"cost-state","modelUsage":{"claude-opus-5-5[1m]":{"costUSD":1.0}}}"#,
            #"{"type":"assistant","timestamp":"\#(ts)","requestId":"r2","message":{"id":"m2","model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":500000}}}"#,
            #"{"type":"cost-state","modelUsage":{"claude-opus-5-5[1m]":{"costUSD":2.5}}}"#,
        ]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let fmt = R.localDayFormatter()
        let entries = R.parseClaudeFile(url, fmt: fmt)
        XCTAssertEqual(entries.count, 2)
        let day = try XCTUnwrap(R.daily(entries: entries, localDay: entries[0].localDay))
        XCTAssertEqual(day.totalCost, 2.5, accuracy: 1e-9, "the last cumulative cost-state wins")
    }
}
