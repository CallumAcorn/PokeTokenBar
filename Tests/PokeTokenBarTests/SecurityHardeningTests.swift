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
