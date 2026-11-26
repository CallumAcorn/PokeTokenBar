import XCTest
@testable import PokeTokenBar

/// Guards added by the 2026-11 security and operational review. Each test reproduces the input
/// that caused the defect, so removing the guard makes it fail.
final class SecurityUpliftTests: XCTestCase {
    private typealias R = LocalUsageReader

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uplift-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func claudeLine(id: String, output: Int) -> String {
        #"{"type":"assistant","requestId":"r-\#(id)","timestamp":"2026-07-02T01:00:00.000Z","message":{"id":"m-\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":\#(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
    }

    // MARK: SQLite counters

    /// An Int64 column near the maximum trapped on the first addition (Hermes adds two columns).
    func testSQLiteCountersAreClampedSoSumsCannotTrap() {
        let cap = R.maxParsedTokenValue
        XCTAssertEqual(LocalAdditionalUsageReader.clampedCounter(Int64.max), cap)
        XCTAssertEqual(LocalAdditionalUsageReader.clampedCounter(-5), 0)
        XCTAssertEqual(LocalAdditionalUsageReader.clampedCounter(42), 42)
        let a = LocalAdditionalUsageReader.clampedCounter(Int64.max)
        let (sum, overflow) = a.addingReportingOverflow(a)
        XCTAssertFalse(overflow, "two clamped counters must add without overflow")
        XCTAssertEqual(sum, cap * 2)
    }

    // MARK: Claude parser, chunked

    func testChunkedParseMatchesWholeFileParseAtAnyChunkSize() throws {
        let url = tempDir().appendingPathComponent("s.jsonl")
        let lines = (1...40).map { claudeLine(id: "\($0)", output: $0) }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        let fmt = R.localDayFormatter()
        let whole = try XCTUnwrap(R.parseClaudeFile(url, fromOffset: 0, fmt: fmt))
        XCTAssertEqual(whole.entries.count, 40)
        for chunk in [1, 7, 64, 333, 4096] {
            let parsed = try XCTUnwrap(R.parseClaudeFile(url, fromOffset: 0, fmt: fmt, chunkBytes: chunk))
            XCTAssertEqual(Set(parsed.entries.map(\.id)), Set(whole.entries.map(\.id)), "chunk \(chunk)")
            XCTAssertEqual(parsed.entries.map(\.output).reduce(0, +), whole.entries.map(\.output).reduce(0, +))
            XCTAssertEqual(parsed.newOffset, whole.newOffset, "chunk \(chunk): the offset ends at the last newline")
        }
    }

    /// A newline-free run longer than the line cap is dropped instead of growing the buffer, and
    /// the records after it are still read.
    func testOversizeLineIsDroppedAndParsingContinues() throws {
        let url = tempDir().appendingPathComponent("s.jsonl")
        let text = claudeLine(id: "1", output: 5) + "\n" + String(repeating: "x", count: 5_000) + "\n"
            + claudeLine(id: "2", output: 7) + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let parsed = try XCTUnwrap(R.parseClaudeFile(url, fromOffset: 0, fmt: R.localDayFormatter(),
                                                     chunkBytes: 256, maxLineBytes: 1_000))
        XCTAssertEqual(Set(parsed.entries.map(\.output)), [5, 7])
        XCTAssertEqual(parsed.newOffset, text.utf8.count)
    }

    /// The offset comes from the cache file. `UInt64(-1)` is a trap, not an error.
    func testNegativeOffsetIsRefusedNotTrapped() throws {
        let url = tempDir().appendingPathComponent("s.jsonl")
        try (claudeLine(id: "1", output: 5) + "\n").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(R.parseClaudeFile(url, fromOffset: -1, fmt: R.localDayFormatter()))
    }

    // MARK: Cache offsets

    private func tamperOffsets(_ cacheFile: URL, to offset: Int) throws {
        let raw = try Data(contentsOf: cacheFile)
        let decompressed = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: decompressed) as? [String: Any])
        var claude = try XCTUnwrap(json["claude"] as? [String: [String: Any]])
        XCTAssertFalse(claude.isEmpty)
        for (k, var blob) in claude { blob["offset"] = offset; claude[k] = blob }
        json["claude"] = claude
        try JSONSerialization.data(withJSONObject: json).write(to: cacheFile, options: .atomic)
    }

    /// A tampered or corrupt cache offset (negative, or past the end) must fall back to a full
    /// parse: before, -1 trapped on launch and a huge offset silently froze the file's totals.
    func testTamperedCacheOffsetFallsBackToAFullParse() async throws {
        for bad in [-1, 1_000_000_000_000] {
            let dir = tempDir()
            let root = dir.appendingPathComponent("projects")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("a.jsonl")
            let cacheFile = dir.appendingPathComponent("cache.json")
            let first = claudeLine(id: "1", output: 111) + "\n"
            try first.write(to: file, atomically: true, encoding: .utf8)
            _ = await LocalUsageCache(claudeRoot: root, fileURL: cacheFile).claudeEntries(modifiedSince: .distantPast)
            try tamperOffsets(cacheFile, to: bad)

            try (first + claudeLine(id: "2", output: 222) + "\n").write(to: file, atomically: true, encoding: .utf8)
            let entries = await LocalUsageCache(claudeRoot: root, fileURL: cacheFile)
                .claudeEntries(modifiedSince: .distantPast)
            XCTAssertEqual(Set(entries.map(\.output)), [111, 222], "offset \(bad)")
        }
    }

    /// A file replaced by a larger, different one is not "appended to". Resuming at the old offset
    /// read from the middle of a line and kept the old file's entries.
    func testReplacedLargerFileIsReadFromTheStart() async throws {
        let dir = tempDir()
        let root = dir.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("a.jsonl")
        let cache = LocalUsageCache(claudeRoot: root, fileURL: dir.appendingPathComponent("cache.json"))
        try (claudeLine(id: "old", output: 111) + "\n").write(to: file, atomically: true, encoding: .utf8)
        _ = await cache.claudeEntries(modifiedSince: .distantPast)

        // Different first bytes, and longer than the old file.
        let replacement = #"{"note":"rewritten"}"# + "\n" + claudeLine(id: "new1", output: 5) + "\n"
            + claudeLine(id: "new2", output: 6) + "\n"
        try replacement.write(to: file, atomically: true, encoding: .utf8)
        let entries = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(Set(entries.map(\.output)), [5, 6], "the old file's entry must not survive a replacement")
    }

    // MARK: Online endpoints

    /// A session id is spliced into the path and comes from an invite link or the server.
    func testEndpointPathRejectsTraversalAndOddCharacters() {
        XCTAssertNotNil(OnlineStore.endpointURL(from: "https://srv.test", path: "/trades/abc-123_X/join"))
        XCTAssertNotNil(OnlineStore.endpointURL(from: "https://srv.test", path: "/health"))
        for bad in ["/trades/x/../../battles/join", "/trades//join", "/trades/a%2Fb/join", "/trades/a?b=c/join",
                    "/trades/a b/join", "trades/x", "/trades/" + String(repeating: "a", count: 300)] {
            XCTAssertNil(OnlineStore.endpointURL(from: "https://srv.test", path: bad), bad)
        }
    }

    func testOnlineSessionKeepsNothingOnDisk() {
        let config = OnlineStore.urlSession.configuration
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
    }

    // MARK: Credentialed endpoints

    /// `CLOUD_CODE_URL` chooses where the Google bearer token is sent.
    func testCloudCodeOverrideAcceptsOnlyHTTPSGoogleAPIHosts() {
        typealias P = AntigravityRateLimitsProvider
        XCTAssertEqual(P.overrideEndpoint(from: "https://staging-cloudcode-pa.googleapis.com")?.absoluteString,
                       "https://staging-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")
        for bad in ["https://evil.example", "http://cloudcode-pa.googleapis.com", "https://googleapis.com.evil.example",
                    "https://user:pw@cloudcode-pa.googleapis.com", "https://evil.example/.googleapis.com", "", "not a url"] {
            XCTAssertNil(P.overrideEndpoint(from: bad), bad)
        }
        XCTAssertNil(P.overrideEndpoint(from: nil))
    }

    func testCredentialedSessionKeepsNothingOnDisk() {
        let config = CredentialedSession.shared.configuration
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
    }

    func testUpdateBannerOnlyOpensThisRepositorysReleasePages() {
        XCTAssertTrue(UpdateChecker.isTrustedReleaseURL("https://github.com/CallumAcorn/PokeTokenBar/releases/tag/v2.5.1-hardened.20"))
        for bad in ["https://github.com/attacker/PokeTokenBar/releases/tag/v9.9.9",
                    "https://github.com/CallumAcorn/PokeTokenBar-evil/releases/tag/v9",
                    "https://github.com/login?return_to=/CallumAcorn/PokeTokenBar/releases/",
                    "http://github.com/CallumAcorn/PokeTokenBar/releases/tag/v1",
                    "https://evil@github.com/CallumAcorn/PokeTokenBar/releases/tag/v1",
                    "https://github.com.evil.example/CallumAcorn/PokeTokenBar/releases/tag/v1"] {
            XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(bad), bad)
        }
    }

    // MARK: Peer-supplied mons and imported saves

    func testSanitizerBoundsPeerControlledSizes() {
        var mon = MonState(baseID: 1, pathIDs: Array(1...500), plannedPathIDs: Array(1...500), stageIndex: 0,
                           usedAtStage: 0, rarity: .common, totalForms: 1)
        mon.id = String(repeating: "i", count: 10_000)
        mon.ability = String(repeating: "a", count: 10_000)
        let clean = SaveTransfer.sanitizedMon(mon)
        XCTAssertEqual(clean.pathIDs.count, SaveTransfer.maxChainLength)
        XCTAssertEqual(clean.plannedPathIDs.count, SaveTransfer.maxChainLength)
        XCTAssertEqual(clean.id.count, SaveTransfer.maxIdentifierLength)
        XCTAssertEqual(clean.ability?.count, SaveTransfer.maxIdentifierLength)
        XCTAssertLessThan(clean.stageIndex, clean.pathIDs.count)
    }

    /// A normal mon (UUID id, short chain) passes through unchanged.
    func testSanitizerLeavesOrdinaryMonsAlone() {
        var mon = MonState(baseID: 1, pathIDs: [1, 2, 3], plannedPathIDs: [1, 2, 3], stageIndex: 1,
                           usedAtStage: 10, rarity: .common, totalForms: 3)
        mon.ability = "overgrow"
        let clean = SaveTransfer.sanitizedMon(mon)
        XCTAssertEqual(clean.id, mon.id)
        XCTAssertEqual(clean.pathIDs, [1, 2, 3])
        XCTAssertEqual(clean.ability, "overgrow")
        XCTAssertEqual(clean.stageIndex, 1)
    }

    func testOversizeSaveFileIsRefusedBeforeItIsRead() throws {
        let url = tempDir().appendingPathComponent("huge.json")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SaveTransfer.maxFileBytes) + 1)   // sparse, no real bytes
        try handle.close()
        XCTAssertThrowsError(try SaveTransfer.decode(contentsOf: url)) { error in
            guard case SaveTransferError.fileTooLarge = error else { return XCTFail("\(error)") }
        }
    }
}
