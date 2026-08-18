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

    /// The shipped default: a fresh install does not read the Claude credential until asked.
    ///
    /// `UsageStoreTests` opts back in for its own fixtures, so without this test nothing would
    /// notice the default silently reverting to upstream's.
    @MainActor
    func testCredentialAccessIsDisabledByDefault() {
        let suite = "ptb-hardening-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        // autoRefresh: false — nothing fetches, this only reads the initialised value.
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        XCTAssertTrue(store.disableKeychainAccess,
                      "credential access must be off on a fresh install in this fork")
    }

    /// An explicit prior choice survives — the hardened default applies only when the key was
    /// never written, so upgrading does not silently override what the user picked.
    @MainActor
    func testExplicitCredentialChoiceIsPreserved() {
        let suite = "ptb-hardening-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "disableKeychainAccess")

        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        XCTAssertFalse(store.disableKeychainAccess,
                       "an explicit user choice must not be overwritten by the hardened default")
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
