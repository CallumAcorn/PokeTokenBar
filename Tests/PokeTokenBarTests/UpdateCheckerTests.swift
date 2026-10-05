import XCTest
@testable import PokeTokenBar

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    // MARK: Cooldown and tag validation (upstream #321, ported)

    @MainActor func testFailedCheckDoesNotStartTheCooldown() async {
        nonisolated(unsafe) var calls = 0
        nonisolated(unsafe) var reply: UpdateChecker.LatestRelease?
        let checker = UpdateChecker(currentVersion: "2.5.1-hardened.11", clock: { Date(timeIntervalSince1970: 0) },
                                          fetchLatest: { calls += 1; return reply })
        await checker.check()
        XCTAssertEqual(calls, 1)
        reply = .init(tag: "v2.5.1-hardened.12", url: "https://github.com/CallumAcorn/PokeTokenBar/releases/tag/v2.5.1-hardened.12")
        await checker.check()
        XCTAssertEqual(calls, 2, "a failed check must not block the next attempt for 30 minutes")
        let shown = checker.available?.version
        XCTAssertEqual(shown, "2.5.1-hardened.12")
        await checker.check()
        XCTAssertEqual(calls, 2, "a successful check does start the cooldown")
    }

    @MainActor func testUntrustedURLIsAFailedCheck() async {
        nonisolated(unsafe) var calls = 0
        let checker = UpdateChecker(currentVersion: "2.5.1-hardened.11", clock: { Date(timeIntervalSince1970: 0) },
                                          fetchLatest: { calls += 1; return .init(tag: "v9.9.9", url: "http://evil.example/x") })
        await checker.check()
        await checker.check()
        XCTAssertEqual(calls, 2)
        let shown = checker.available
        XCTAssertNil(shown)
    }

    func testReleaseTagValidationAcceptsTheForkScheme() {
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("v2.5.1-hardened.12"), "2.5.1-hardened.12")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("2.6.0"), "2.6.0")
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.6.0-beta.1"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("latest"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("2.6"))
    }
}
