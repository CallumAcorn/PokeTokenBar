# Fork hardening

What this fork changes relative to `chattymin/PokeTokenBar`, and why. Upstream is well built and
carries no malware; every item here is about reducing what a *future* compromise could reach, or
about giving the user a choice they did not previously have.

Findings are numbered as they were in the review that prompted this work.

## Defaults changed

Three defaults are inverted relative to upstream. Everything else keeps upstream behaviour.

| Setting | Upstream | Here | Effect if you change nothing |
|---|---|---|---|
| Credential access | Enabled | Enabled | Unchanged. See MED 4 for the automatic-refresh interlock |
| Shell path resolution | Enabled | **Disabled** | Tools outside the static path list are not found |
| Login agent `KeepAlive` | Always on with login | **Opt-in** | App does not restart itself after a crash |

An explicit prior choice is never overwritten. The defaults apply only when the key has never
been written, so upgrading does not silently change a setting you already made.

---

## HIGH 1 — No integrity verification in the release chain

**Upstream:** the cask declares `sha256 :no_check` against a GitHub release URL. Release assets
are mutable, so brew installs whatever bytes are served at that moment. The release zip is built
and uploaded from the maintainer's laptop; CI only runs tests, so nothing links the published
artefact to the reviewed source.

**Here:**

- `scripts/release.sh` computes a SHA256 of the zip, publishes it as a `SHA256SUMS` release asset,
  writes it into the cask, and **refuses to publish** if the hash cannot be produced or if the
  cask still says `:no_check`.
- `.github/workflows/release-provenance.yml` builds the tagged source on a GitHub runner and
  records a signed build-provenance attestation, verifiable with `gh attestation verify`.

**What this does not fix.** A CI build cannot be byte-identical to a locally signed release, so
the attestation covers the CI artefact, not the maintainer's upload. It makes a discrepancy
*detectable* rather than impossible. Building from source is still the only complete answer, and
`SECURITY.md` says so plainly instead of implying the attestation is a guarantee it is not.

## HIGH 2 — Cask stripped the quarantine attribute

**Upstream:** a `postflight` block runs `xattr -cr` on the installed app, removing
`com.apple.quarantine` before first launch so Gatekeeper never assesses it. That is how an
un-notarised build is made to launch silently.

**Here:** `packaging/Casks/poke-token-bar.rb` has no `postflight` and no `xattr` call. Because the
app is self-signed rather than Developer ID signed, macOS will block the first launch and the user
must right-click → Open, or clear the attribute themselves. The bypass becomes a conscious,
auditable decision by the person installing rather than something the installer performs for them.

Fully closing this needs an Apple Developer ID and notarisation, which this fork does not have.

## HIGH 3 — Persistence with auto-restart

**Upstream:** one launchd agent with `KeepAlive.SuccessfulExit=false`, registered by the single
"launch at login" toggle. The app therefore reappears after being killed.

**Here:** two agents ship in the bundle and exactly one is ever registered. The default keeps the
existing label and drops `KeepAlive`, so existing registrations stay valid across the upgrade and
no migration is needed. Auto-restart moves to its own switch, off by default.

`UpdateChecker` now kickstarts either label after a brew upgrade.

## MED 4 — Claude OAuth token handling

The feature cannot exist without reading the token, so this is about blast radius:

- Automatic refresh may read the Keychain, but only after a no-UI read has been observed to
  succeed on this machine, bounded by a 2s timeout and a circuit breaker. Until proven, a
  background poll behaves as if the Keychain were unavailable and cannot raise a prompt.
- The request now uses a dedicated **ephemeral** `URLSession` with no URL cache, cookie storage or
  credential storage, created once and reused. A session built per request would leak its delegate
  queue on throwing paths.
- `Info.plist` declares ATS explicitly (`NSAllowsArbitraryLoads` false) so a future plaintext
  exception shows up in a diff rather than being invisible because it matched the default.

## MED 5 — The Keychain opt-out did not cover the credentials file

**Upstream:** the gate wrapped only the Keychain read. `~/.claude/.credentials.json` was read
before it, on every automatic poll, with the setting on. An already-cached token also kept being
served after the user opted out.

**Here:** the gate is the first statement in `OAuthAccessTokenCache.accessToken()`, ahead of the
in-memory cache and every credential source, and it clears the cache on the way out. The setting
is relabelled from "Disable Keychain access" to "Disable credential access" in all four languages,
because that is now what it does.

Pinned by `SecurityHardeningTests.testCredentialGateBlocksBeforeAnySourceIsRead`.

## MED 6 — No hardened runtime

**Upstream:** `codesign --force -s <identity>` with no `--options runtime`. Without library
validation, any code running as the user can inject a dylib into a process that holds a live OAuth
token.

**Here:** `--options runtime` on both the identity and ad-hoc paths, and the build fails if the
flag is not present on the signed bundle afterwards. No entitlements are granted, which is the
most restrictive configuration.

Verified safe: all 32 linked libraries resolve under `/usr/lib` or `/System`, the single `dlopen`
targets a system framework, and a signed binary runs cleanly under the hardened runtime. App
Sandbox is **not** adopted: the app's entire purpose is reading files across the home directory,
so a sandbox would need such broad exceptions that it would not be meaningful.

## MED 7 — Login shell spawn

**Upstream:** `$SHELL -ilc` is spawned to resolve tool paths, executing the user's whole
interactive profile inside the app, with `$SHELL` taken from the environment and checked only for
executability.

**Here:** off by default, with the static path list covering the common installs. When enabled,
`$SHELL` is accepted only if `/etc/shells` lists it.

The fallback is deliberate: an unlisted shell falls back to `/bin/zsh` rather than returning nil.
Returning nil is the tempting "secure" reflex and it is wrong here, because it would silently stop
provider detection for anyone running a shell the system does not list. That is a functional
regression, not a security win. Pinned by `testLoginShellFallsBackWhenUnlisted`.

## LOW — Sprite downloads written unchecked

**Upstream:** any 200 response body is written to Application Support and decoded.

**Here:** the response must come from `raw.githubusercontent.com` over HTTPS, be at most 5 MB, and
start with PNG, GIF, JPEG or WebP magic bytes. Four formats are accepted rather than just PNG so a
legitimate sprite is never rejected; a RIFF container that is not WebP is refused.

## CI supply chain

- Every action pinned to a commit SHA. A tag is a movable pointer, so whoever can push tags to the
  action's repository can change what runs.
- Explicit least-privilege `permissions:` blocks. Without one the repository default applies,
  which is frequently read/write for every scope.
- `persist-credentials: false` on checkout, since no job pushes.
- `verify-hardening.sh` fails if an unpinned action reappears.

## Testing

`Tests/PokeTokenBarTests/SecurityHardeningTests.swift` adds 12 tests covering the credential gate,
shell validation, sprite payload validation, and the changed defaults.

Two existing suites (`UsageStoreTests`, `RareCandyGrantIntegrationTests`) now opt into credential
access in `setUp`, because they exercise limit display and candy grants against injected stub
providers and would otherwise be testing the disabled path. They were changed rather than having
production diverge from test behaviour via a bundled-app check, which would have meant the shipped
default was never covered by a test at all.

Full suite: 688 tests, 0 failures. Logic-core line coverage 89.94% against a 75% floor.
