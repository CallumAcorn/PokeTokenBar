import XCTest
@testable import PokeTokenBar

/// Regression cover for the hardening changes in this fork. Each test pins a property that a
/// future refactor could quietly undo, so the failure message says what was lost, not just that
/// an assertion tripped.
final class SecurityHardeningTests: XCTestCase {

    override func tearDown() {
        // The gate is process-global memory state. Leaking `true` out of a test would make every
        // later credential test pass for the wrong reason.
        KeychainAccessGate.isDisabled = false
        super.tearDown()
    }

    // MARK: Credential access gate

    /// The opt-out must short-circuit **before** any credential source is touched.
    ///
    /// Previously the gate wrapped only the Keychain read, so with the setting on the app still
    /// read `~/.claude/.credentials.json` on every automatic poll. This asserts the gate is the
    /// first thing `fetch` consults: it must throw `keychainAccessDisabled` rather than any error
    /// that could only come from having gone looking for a credential.
    func testCredentialGateBlocksBeforeAnySourceIsRead() async {
        KeychainAccessGate.isDisabled = true
        do {
            _ = try await OAuthLimitsProvider().fetch(allowKeychainPrompt: true)
            XCTFail("fetch succeeded with credential access disabled — the gate is not being applied")
        } catch let error as LimitsError {
            guard case .keychainAccessDisabled = error else {
                return XCTFail("expected .keychainAccessDisabled, got \(error) — a credential source was consulted before the gate")
            }
        } catch {
            XCTFail("expected LimitsError.keychainAccessDisabled, got \(error)")
        }
    }

    /// `allowKeychainPrompt: false` is the automatic polling path; it must be gated identically.
    func testCredentialGateAppliesToAutomaticPollPath() async {
        KeychainAccessGate.isDisabled = true
        do {
            _ = try await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
            XCTFail("automatic poll succeeded with credential access disabled")
        } catch let error as LimitsError {
            guard case .keychainAccessDisabled = error else {
                return XCTFail("expected .keychainAccessDisabled on the auto path, got \(error)")
            }
        } catch {
            XCTFail("expected LimitsError.keychainAccessDisabled, got \(error)")
        }
    }

    /// Credential access defaults on, matching upstream. The protection is the gate and the
    /// silent-read interlock below, not the default.
    @MainActor
    func testCredentialAccessIsEnabledByDefault() {
        let suite = "ptb-hardening-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        // autoRefresh: false — nothing fetches, this only reads the initialised value.
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        XCTAssertFalse(store.disableKeychainAccess,
                       "credential access defaults on; the gate, not the default, is the control")
    }

    /// An explicit prior choice survives — the default applies only when the key was never
    /// written, so an upgrade never overrides what the user picked.
    @MainActor
    func testExplicitCredentialChoiceIsPreserved() {
        let suite = "ptb-hardening-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "disableKeychainAccess")   // user opted out

        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        XCTAssertTrue(store.disableKeychainAccess,
                      "an explicit opt-out must not be overwritten by the default")
    }

    /// The interlock: until a silent Keychain read has been observed to succeed on this machine,
    /// the automatic path must not call into the Keychain at all.
    ///
    /// Asserted by timing rather than by inspecting the private cache. A `SecItemCopyMatching`
    /// against a locked or unapproved keychain is exactly what blocks for many seconds and puts a
    /// dialog on screen, so "returned promptly" is the property that matters and the one a
    /// regression would break. Anything approaching the 13 seconds upstream measured means the
    /// automatic path reached the Keychain when it should not have.
    func testAutomaticPathReturnsPromptlyWhenSilentReadUnverified() async throws {
        let key = "silentKeychainReadVerified"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        KeychainAccessGate.isDisabled = false

        let started = Date()
        _ = try? await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 3,
                          "unverified automatic path must not reach a blocking Keychain call")
    }

    // MARK: Login shell validation

    /// A shell listed in the shells file is used as-is.
    func testLoginShellAcceptsSanctionedShell() throws {
        let shells = try writeShellsFile("# comment\n/bin/zsh\n/bin/bash\n")
        let resolved = BinaryLocator.resolveLoginShell(
            environment: ["SHELL": "/bin/bash"], shellsFile: shells, fallback: "/bin/zsh")
        XCTAssertEqual(resolved, "/bin/bash")
    }

    /// An unlisted `$SHELL` falls back rather than failing.
    ///
    /// Returning nil here would be the "secure" reflex and the wrong call: it silently stops
    /// provider detection for anyone running a shell the system does not list. The fallback keeps
    /// the feature working while still refusing to execute an arbitrary attacker-set binary.
    func testLoginShellFallsBackWhenUnlisted() throws {
        let shells = try writeShellsFile("/bin/zsh\n")
        let resolved = BinaryLocator.resolveLoginShell(
            environment: ["SHELL": "/tmp/definitely-not-a-sanctioned-shell"],
            shellsFile: shells, fallback: "/bin/zsh")
        XCTAssertEqual(resolved, "/bin/zsh", "unlisted SHELL should fall back, not disable resolution")
    }

    /// Comment and blank lines in the shells file are not treated as shell paths.
    func testLoginShellIgnoresCommentsAndBlanks() throws {
        let shells = try writeShellsFile("\n# /bin/evil\n\n/bin/zsh\n")
        let resolved = BinaryLocator.resolveLoginShell(
            environment: ["SHELL": "# /bin/evil"], shellsFile: shells, fallback: "/bin/zsh")
        XCTAssertEqual(resolved, "/bin/zsh")
    }

    /// A missing shells file must not fail open onto whatever `$SHELL` says.
    func testLoginShellWithMissingShellsFileFallsBack() {
        let resolved = BinaryLocator.resolveLoginShell(
            environment: ["SHELL": "/tmp/nope"],
            shellsFile: "/tmp/does-not-exist-\(UUID().uuidString)", fallback: "/bin/zsh")
        XCTAssertEqual(resolved, "/bin/zsh")
    }

    /// Shell resolution is opt-in in this fork. If this flips, every provider lookup starts
    /// spawning the user's interactive profile again.
    func testShellResolutionIsDisabledByDefault() {
        let key = BinaryLocator.shellResolutionDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } }

        XCTAssertTrue(BinaryLocator.isShellResolutionDisabled,
                      "shell resolution must default to disabled in this fork")
    }

    // MARK: Sprite payload validation

    func testSpriteMagicAcceptsRealImageHeaders() {
        XCTAssertTrue(SpriteStore.hasImageMagic(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), "PNG")
        XCTAssertTrue(SpriteStore.hasImageMagic(Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), "GIF89a")
        XCTAssertTrue(SpriteStore.hasImageMagic(Data([0xFF, 0xD8, 0xFF, 0xE0])), "JPEG")
        let webp: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]
        XCTAssertTrue(SpriteStore.hasImageMagic(Data(webp)), "WebP")
    }

    func testSpriteMagicRejectsNonImagePayloads() {
        XCTAssertFalse(SpriteStore.hasImageMagic(Data()), "empty")
        XCTAssertFalse(SpriteStore.hasImageMagic(Data("<!DOCTYPE html>".utf8)), "HTML error page")
        XCTAssertFalse(SpriteStore.hasImageMagic(Data([0x4D, 0x5A])), "truncated / MZ")
        XCTAssertFalse(SpriteStore.hasImageMagic(Data("#!/bin/sh\necho hi".utf8)), "shell script")
        // RIFF container that is not WebP (e.g. a WAV) must not pass.
        let wav: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45]
        XCTAssertFalse(SpriteStore.hasImageMagic(Data(wav)), "RIFF/WAVE")
    }

    func testSpriteHostAllowListIsNarrow() {
        XCTAssertEqual(SpriteStore.allowedSpriteHosts, ["raw.githubusercontent.com"])
    }

    // MARK: helpers

    private func writeShellsFile(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shells-\(UUID().uuidString)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }
}

/// Inventory bounds on the save trust boundary.
///
/// `SaveTransfer.sanitized()` is the single choke point for both `load()` and save import, and it
/// exists specifically so that out-of-range values cannot reach arithmetic that traps. It clamped
/// the token fields but not `inventory`, whose values feed `+= 1` (shop purchase) and `+= g.count`
/// (candy grant). A save carrying `Int.max` rare candy therefore crashed the process on the next
/// purchase, and kept crashing on relaunch because the value had been persisted.
final class SaveInventoryBoundsTests: XCTestCase {

    func testSanitizedClampsInventoryUpperBound() {
        var state = CompanionState()
        state.inventory[ItemKind.rareCandy.rawValue] = Int.max
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.inventory[ItemKind.rareCandy.rawValue], SaveTransfer.maxTokenValue,
                       "Int.max rare candy must be clamped — `inventory += 1` traps on overflow")
    }

    func testSanitizedClampsInventoryNegatives() {
        var state = CompanionState()
        state.inventory[ItemKind.mint.rawValue] = Int.min
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.inventory[ItemKind.mint.rawValue], 0,
                       "negative counts must floor at 0 — `itemCount - 1` traps at Int.min")
    }

    /// The clamp must not disturb ordinary saves.
    func testSanitizedLeavesRealisticInventoryAlone() {
        var state = CompanionState()
        state.inventory[ItemKind.rareCandy.rawValue] = 12
        state.inventory[ItemKind.shinyCharm.rawValue] = 1
        let clean = SaveTransfer.sanitized(state)
        XCTAssertEqual(clean.inventory[ItemKind.rareCandy.rawValue], 12)
        XCTAssertEqual(clean.inventory[ItemKind.shinyCharm.rawValue], 1)
    }

    /// The overflow is genuinely reachable through the real purchase path, not just theoretical.
    /// Guard the arithmetic that would trap so the assertion documents the trigger.
    func testPurchaseArithmeticIsSafeAfterSanitising() {
        var state = CompanionState()
        state.inventory[ItemKind.rareCandy.rawValue] = Int.max
        let clean = SaveTransfer.sanitized(state)
        let count = clean.inventory[ItemKind.rareCandy.rawValue] ?? 0
        // This is the operation CompanionStore.buy() performs. It must not overflow.
        XCTAssertFalse(count.addingReportingOverflow(1).overflow,
                       "sanitised inventory must survive the += 1 in buy()")
        XCTAssertFalse(count.subtractingReportingOverflow(1).overflow,
                       "sanitised inventory must survive the - 1 in consumeRareCandy()")
    }
}

/// Phase 0 calibration instrumentation. `makeSample` is pure, so these run without touching the
/// filesystem; `record` is the only impure part and is gated on `AppEnv.isBundledApp`.
final class CalibrationLogTests: XCTestCase {

    private func sample() -> CalibrationLog.Sample {
        var limits = try! JSONDecoder().decode(LimitStatus.self, from: Data("""
        {"five_hour":{"utilization":12.5},"seven_day":{"utilization":16.0},
         "limits":[{"kind":"weekly_scoped","group":"weekly","percent":8.0,
                    "scope":{"model":{"display_name":"Opus 4.8"}}}]}
        """.utf8))
        limits.subscriptionType = "max"
        limits.rateLimitTier = "default_claude_max_20x"
        let today = DailyUsage(date: "2026-08-19", inputTokens: 10, outputTokens: 20,
                               cacheCreationTokens: 30, cacheReadTokens: 40,
                               totalTokens: 100, totalCost: 1.5)
        return CalibrationLog.makeSample(
            now: Date(timeIntervalSince1970: 1_700_000_000),
            limits: limits,
            snapshots: [(id: "claude_code", today: today)])
    }

    /// The four token kinds must survive separately. Lumping them into a total is exactly what
    /// prevents the fit from weighting cache reads differently from fresh generation, which is one
    /// of the three causes of the 4x spread this study exists to resolve.
    func testTokenKindsAreRecordedSeparately() {
        let p = sample().providers.first
        XCTAssertEqual(p?.input, 10)
        XCTAssertEqual(p?.output, 20)
        XCTAssertEqual(p?.cacheWrite, 30)
        XCTAssertEqual(p?.cacheRead, 40)
        XCTAssertEqual(p?.total, 100)
    }

    /// Every window is captured, including the per-model scoped entries.
    func testAllWindowsAreCaptured() {
        let s = sample()
        XCTAssertEqual(s.fh, 12.5)
        XCTAssertEqual(s.sd, 16.0)
        XCTAssertEqual(s.scoped.first?.model, "Opus 4.8")
        XCTAssertEqual(s.scoped.first?.percent, 8.0)
    }

    /// No account, org, device or user identifier may reach the file. `plan`/`tier` are
    /// subscription attributes, needed to interpret window size, and are not identifiers.
    func testEncodedSampleCarriesNoIdentifiers() throws {
        let json = String(data: try JSONEncoder().encode(sample()), encoding: .utf8)!.lowercased()
        for banned in ["org", "account", "email", "uuid", "device", "token\":\"", "bearer", "@"] {
            XCTAssertFalse(json.contains(banned),
                           "calibration sample must not encode '\(banned)' — got \(json)")
        }
    }

    /// Study logging is on by default; it is the only route to the Phase 1 decision gate.
    func testLoggingDefaultsOn() {
        let key = CalibrationLog.defaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } }
        XCTAssertTrue(CalibrationLog.isEnabled)
    }
}

/// Attribution rules for crediting growth to work that leaves no local transcript.
///
/// The anti-double-count problem is real: the weekly window moves for Claude Code too, and
/// attributing the residual needs a tokens-per-percent constant the study measured at a 20.69x
/// spread. So attribution uses the **quiet share of the accumulated period** instead of a
/// subtraction, and needs no constant to decide *whose* usage it was.
///
/// The first version demanded local tokens be flat in the same poll as the tick. Measured on real
/// data that fired once in 619 intervals over five days — not because quiet polls are rare (55.4%
/// were) but because a whole-percent tick landing inside a quiet two-minute slice is a coincidence.
final class ExternalUsageCreditTests: XCTestCase {

    func testFullyQuietPeriodEarnsTheWholePoint() {
        let xp = ExternalUsageCredit.credit(previousPercent: 10, currentPercent: 11,
                                            quietPolls: 180, activePolls: 0)
        XCTAssertEqual(xp, ExternalUsageCredit.tokensPerPercent)
    }

    /// The regression that motivated the rewrite: a tick observed in a busy poll, after a period
    /// that was mostly quiet, must still pay. The old rule awarded nothing here.
    func testMostlyQuietPeriodStillPaysProportionally() {
        let xp = ExternalUsageCredit.credit(previousPercent: 10, currentPercent: 11,
                                            quietPolls: 150, activePolls: 50)
        XCTAssertEqual(xp, Int(Double(ExternalUsageCredit.tokensPerPercent) * 0.75))
    }

    /// The anti-double-count rule survives: a period with no quiet polls at all earns nothing,
    /// because every bit of that movement could have come from the CLIs.
    func testBusyPeriodEarnsNothing() {
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 10, currentPercent: 11,
                                                quietPolls: 0, activePolls: 200))
    }

    func testNoBaselineAwardsNothing() {
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: nil, currentPercent: 11,
                                                quietPolls: 10, activePolls: 0))
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 10, currentPercent: nil,
                                                quietPolls: 10, activePolls: 0))
    }

    /// Nothing observed yet — a tick on the very first poll has no period to attribute.
    func testNothingObservedAwardsNothing() {
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 10, currentPercent: 11,
                                                quietPolls: 0, activePolls: 0))
    }

    /// A weekly window reset reads as a large negative delta, which must never award or trap.
    func testWindowResetAwardsNothing() {
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 96, currentPercent: 0,
                                                quietPolls: 100, activePolls: 0))
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 10, currentPercent: 10,
                                                quietPolls: 100, activePolls: 0))
    }

    /// One award cannot graduate a companion, whatever the window reports.
    func testAwardIsCapped() {
        let xp = ExternalUsageCredit.credit(previousPercent: 0, currentPercent: 100,
                                            quietPolls: 100, activePolls: 0)
        XCTAssertEqual(xp, ExternalUsageCredit.maxCreditPerInterval)
    }

    /// Non-finite percentages must not reach the Int conversion, which would trap.
    func testNonFinitePercentIsRejected() {
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 0, currentPercent: .infinity,
                                                quietPolls: 10, activePolls: 0))
        XCTAssertNil(ExternalUsageCredit.credit(previousPercent: 0, currentPercent: .nan,
                                                quietPolls: 10, activePolls: 0))
    }

    func testDisabledByDefault() {
        let key = ExternalUsageCredit.defaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } }
        XCTAssertFalse(ExternalUsageCredit.isEnabled)
    }
}

final class UpdateSourceTests: XCTestCase {

    func testUpdatesComeFromThisFork() {
        XCTAssertEqual(UpdateChecker.repo, "CallumAcorn/PokeTokenBar")
        XCTAssertFalse(UpdateChecker.repo.contains("chattymin"),
                       "the update channel must never point at upstream")
    }

    func testCaskTokenDoesNotCollideWithUpstream() {
        XCTAssertNotEqual(UpdateChecker.caskToken, "poke-token-bar",
                          "sharing upstream's cask token lets brew upgrade pull their build")
        XCTAssertEqual(UpdateChecker.caskToken, "poke-token-bar-hardened")
    }
}

/// Version ordering for this fork's `MAJOR.MINOR.PATCH[-hardened.N]` scheme.
///
/// The suffix exists because upstream and this fork shipped different code under identical
/// version strings — both sat at 2.5.1 while upstream released its own 2.5.2.
final class ForkVersionOrderingTests: XCTestCase {

    /// The regression the naive parser caused: `"2.5.1-hardened.1".split(".")` gives
    /// `["2","5","1-hardened","1"]`, `Int("1-hardened")` is nil, the patch collapses to 0, and the
    /// build reads as OLDER than plain 2.5.1 — so the update banner would never fire.
    func testHardenedBuildRanksAboveThePlainRelease() {
        XCTAssertTrue(UpdateChecker.isNewer("2.5.1-hardened.1", than: "2.5.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.5.1", than: "2.5.1-hardened.1"))
    }

    func testHardenedCountersOrderNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("2.5.1-hardened.10", than: "2.5.1-hardened.9"))
        XCTAssertFalse(UpdateChecker.isNewer("2.5.1-hardened.2", than: "2.5.1-hardened.2"))
    }

    /// Core version still dominates the suffix.
    func testCoreVersionBeatsSuffix() {
        XCTAssertTrue(UpdateChecker.isNewer("2.6.0", than: "2.5.1-hardened.99"))
        XCTAssertFalse(UpdateChecker.isNewer("2.5.1-hardened.99", than: "2.6.0"))
    }

    /// Plain semver behaviour is unchanged.
    func testPlainSemverStillWorks() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.0.10"))
        XCTAssertFalse(UpdateChecker.isNewer("2.5.1", than: "2.5.1"))
    }

    /// An unrecognised suffix contributes 0 rather than sorting unpredictably.
    func testUnknownSuffixIsNeutral() {
        XCTAssertFalse(UpdateChecker.isNewer("2.5.1-beta.4", than: "2.5.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.5.1", than: "2.5.1-beta.4"))
    }

    /// The instructions must name the script that exists, not a download.
    func testUpdateCommandsRebuildFromSource() {
        let cmds = UpdateChecker.updateCommands()
        XCTAssertTrue(cmds.contains("git pull"))
        XCTAssertTrue(cmds.contains("./scripts/build-app.sh"))
        XCTAssertFalse(cmds.lowercased().contains("brew"), "no binary exists for brew to install")
    }
}

/// The credential opt-out must cover **every** provider that reads one, not just Claude.
///
/// Upstream's Antigravity provider arrived checking the gate only inside `readKeychain`, while
/// `accessToken` reads `~/.gemini/jetski-standalone-oauth-token` before reaching it. That is the
/// same defect this fork already fixed once for Claude (MED 5), reintroduced by a new provider —
/// which is exactly why this is asserted per provider rather than trusted to review.
final class CredentialGateCoverageTests: XCTestCase {

    override func tearDown() {
        KeychainAccessGate.isDisabled = false
        super.tearDown()
    }

    func testAntigravityProviderHonoursTheGate() async {
        KeychainAccessGate.isDisabled = true
        do {
            _ = try await AntigravityRateLimitsProvider().fetch(allowKeychainPrompt: false)
            XCTFail("Antigravity fetch succeeded with credential access disabled")
        } catch let error as LimitsError {
            guard case .keychainAccessDisabled = error else {
                return XCTFail("expected .keychainAccessDisabled, got \(error) — a credential source was read before the gate")
            }
        } catch {
            XCTFail("expected LimitsError.keychainAccessDisabled, got \(error)")
        }
    }

    /// The user-action path is gated identically — the gate is a promise about reading credentials,
    /// not about which button was pressed.
    func testAntigravityUserActionPathHonoursTheGate() async {
        KeychainAccessGate.isDisabled = true
        do {
            _ = try await AntigravityRateLimitsProvider().fetch(allowKeychainPrompt: true)
            XCTFail("Antigravity fetch succeeded on the user path with credential access disabled")
        } catch let error as LimitsError {
            guard case .keychainAccessDisabled = error else {
                return XCTFail("expected .keychainAccessDisabled on the user path, got \(error)")
            }
        } catch {
            XCTFail("expected LimitsError.keychainAccessDisabled, got \(error)")
        }
    }

    /// [상류 #243 의 교훈만 이식 — 코드는 이식하지 않는다]
    ///
    /// `kSecMatchLimitAll` 을 `kSecReturnData` 와 같이 넣으면 macOS 는 errSecParam(-50) 을 낸다.
    /// 항목이 없어서가 아니라 **파라미터 조합이 무효라서**라, ACL 승인·항목 존재·재로그인 어느
    /// 것으로도 우회되지 않는다. 상류는 "항목이 여럿일 수 있으니 전부 받자"로 고치다 이 조합을
    /// 만들었고, Keychain 에만 자격증명이 있는 사용자는 공식 한도가 **영구히** 안 떴다.
    ///
    /// 이 포크는 아직 단건 조회(`kSecMatchLimitOne`)라 그 결함이 없다. 이 테스트는 미래를 위한
    /// 가드다 — 나중에 누군가 "여러 항목을 한 번에" 로 고치려는 순간 여기서 먼저 걸린다.
    ///
    /// 존재하지 않는 서비스명으로 던지므로 매칭이 0건이고, ACL·프롬프트 경로에 닿지 않는다.
    /// 기대값이 "성공"이 아니라 **"파라미터가 유효하다"** 인 게 요점이다. 딕셔너리 모양만 단정하는
    /// 테스트로는 이 부류를 못 잡는다 — 어떤 조합이 무효인지는 Security 프레임워크만 안다.
    func testKeychainQueryIsAcceptedBySecurityFramework() throws {
        for allowPrompt in [false, true] {
            var probe = OAuthCredentialData.claudeKeychainQuery(allowKeychainPrompt: allowPrompt)
            probe[kSecAttrService as String] = "PTB-NoSuchService-\(UUID().uuidString)"
            var item: CFTypeRef?
            let status = SecItemCopyMatching(probe as CFDictionary, &item)
            XCTAssertNotEqual(status, errSecParam,
                              "prompt=\(allowPrompt): 무효한 파라미터 조합이다 (-50)")
            XCTAssertEqual(status, errSecItemNotFound,
                           "prompt=\(allowPrompt): 매칭 0건이어야 한다 (status=\(status))")
        }
    }
}
