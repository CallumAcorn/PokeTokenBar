---
summary: Disposition of every upstream commit reviewed for this fork — taken, ported, skipped, or declined.
read_when: Before reviewing what this fork is "behind" on, and after every upstream sync.
---

# Upstream merge ledger

## Why this file exists

**GitHub's "N commits behind" counter is meaningless for this fork and will never go down.**

Commits are brought across by `git cherry-pick`, which rewrites them into new SHAs. Upstream's
originals therefore stay "absent" by SHA forever, even when their content is fully merged. At the
time of writing the banner said *22 behind* while only 4 commits were genuinely outstanding.

Without a record, every future review starts by re-deriving all of this from scratch, and
deliberately declined commits get re-proposed as if nobody had considered them.

Use `./scripts/upstream-status.sh`, which subtracts this ledger from `git cherry` and prints only
what genuinely needs a decision.

## How to use it

After syncing, run the script. For anything it lists as **UNREVIEWED**, decide and add a row here.
Rows are permanent: a declined commit stays declined until someone deliberately changes the row.

| Disposition | Meaning |
|---|---|
| `taken` | Cherry-picked as-is |
| `ported` | Reimplemented, because this fork's model differs |
| `skipped` | Not applicable here — the code it touches does not exist in this fork |
| `declined` | Applicable, and deliberately not wanted |
| `pending` | Decided to take, not yet applied. Carries the reason it is waiting, so it stays out of UNREVIEWED without being forgotten |

## Ledger

| Upstream SHA | PR | Disposition | Note |
|---|---|---|---|
| `12d42181` | #172 | taken | Popover outside-click monitor made idempotent |
| `d16c3ea4` | #158 | **ported** | Representative Pokémon. Upstream reads `state.active`; this fork uses `party` + `trainingSlotID`, so it was reimplemented on `dexUnlocked`. Menu bar only: the floating pet here is a per-mon toggle |
| `eff18bbe` | #181 | taken | Codex usage lost after session archiving |
| `052eacf3` | #174/#180 | taken | Flush `AppLog` on the `willTerminate` path |
| `7a7149fe` | #184 | taken | Bound memory parsing large Codex rollouts |
| `28560eb5` | #192 | taken | Defect-log entry + guard-reachability rule in `CLAUDE.md` |
| `566818ac` | #175/#186 | **skipped** | Fixes the `pgrep` loop inside `launchDetachedUpgrade`, which this fork deleted when releases went source-only. No update loop remains |
| `7422507a` | #182 | taken | Antigravity 2.0/IDE multi-root discovery |
| `8726908e` | #178/#179 | taken | Skip the Kiro rescan when the database is unchanged |
| `7e435665` | #204 | taken | Antigravity step-timestamp defect-log correction (deferred until #182 landed) |
| `bd0bba9c` | #194 | taken | Sprite aspect ratio via `SpriteFit`. Chosen over cropping: preserving the whole sprite beats clipping tall ones |
| `ad9e75e2` | #198 | taken | Prices `claude-fable-5` — this account uses a Fable window |
| `fe31abf9` | #216 | **declined** | `@MainActor` annotations for swift.org toolchains. This fork builds with Xcode, where it already compiles; 11 files touched, 8 overlapping this fork's own changes. Revisit only if a contributor uses a standalone toolchain |
| `40f41082` | #199 | **declined** | Labels limits with the account's **email and organisation**. Adds PII to the app and a second authenticated call to another undocumented endpoint, to solve account-switching confusion that does not occur here. Upstream tests referencing `l.limitsAccount` are removed rather than stubbed |
| `9bb7deeb` | #177/#187 | taken | Per-provider additional scan folders |
| `136e0620` | #185 | taken | French UI. `t()` gained a 5th argument; this fork's own strings pass `nil` and fall back to English rather than carry unreviewed translations |
| `de6c9960` | #210 | taken | Antigravity 2.0/IDE official rate limits |
| `423dd9ca` | #219 | taken | French values for the Antigravity limit strings |
| `1458f5bc` | #220 | **skipped** | Empty here — its content already arrived via #219 and the localisation rebase |
| `66ce4984` | #221 | taken | `KeychainReader` query counter. Composes with this fork's silent-read interlock; the Antigravity provider needed an extra fix so the credential opt-out actually covers it |
| `5d1ab049` | #189 | taken | Pi Agent usage tracking |
| `1ecf87f9` | #215 | taken | Brazilian Portuguese UI, same fallback treatment as French |
| `a6ed409e` | #222 | taken | Antigravity session notice routed through the localisation table |
| `d1866162` | #223 | taken | README coverage for the representative pin, Antigravity limits and scan folders |
| `4c29ca0f` | — | **declined** | Upstream's `release: bump version to 2.5.2`. This fork versions as `MAJOR.MINOR.PATCH-hardened.N`; taking upstream's bump would put different code under their version string, which is the collision the suffix exists to prevent |

## Standing decisions

These outlive individual commits. A future upstream change that reintroduces one should be
declined for the same reason, not re-litigated.

- **No account identity in the app.** Anything fetching an email, organisation, or account name is
  declined. See #199.
- **No binaries attached to releases.** Without a Developer ID a downloaded build is blocked by
  Gatekeeper, and telling users to bypass it is the pattern this fork removed from the upstream
  cask. `verify-hardening.sh` enforces this.
- **The update channel is this fork.** `UpdateChecker.repo` and the cask token must never point at
  or collide with upstream. Enforced by `verify-hardening.sh`.
- **Fork-only strings are not machine-translated.** They fall back to English, which is visibly
  untranslated. An invented translation looks exactly as authoritative as a reviewed one.
| `73749c7d` | #193 | taken | Invisible text in the floating pet hover callout. The callout is AppKit (`NSTextField` + layer-backed `NSView`), so semantic colours resolve against different appearances unless snapshotted together. Conflicted with our `onOpenPopover` doc comment; both kept |
| `79ba760e` | #211 | skipped | Raising badge only on the current evolution stage. **This fork does not have the bug.** Upstream hangs `isRaising` off `DexSpecies`, so the badge lit every species in the line; our dex rework replaced that model with `dexUnlocked` and `DexSpecies` carries no raising flag at all. Every Raising badge here keys off an individual (`entry.monID == trainingSlotID`, or the mon in the PC row), so it cannot appear on a past stage. Attempted as a cherry-pick, hit four structural conflicts, and abandoned once the model divergence was clear |
| `1ff36e1e` | #243 | **ported** | errSecParam(-50) from `kSecMatchLimitAll` + `kSecReturnData`. The code fix repairs damage from #232, which this fork never took: we query `kSecMatchLimitOne`, the valid combination, so the bug does not exist here. Ported the **guard only** — `claudeKeychainQuery` extracted so the test fires the production query at the real Security framework, plus the defect-log rule. Verified by injecting `kSecMatchLimitAll` and watching it return -50 |
| `e81e620b` | #232 | declined | Resolve Claude OAuth across multiple Keychain entries. This is what introduced the errSecParam bug above, and taking it obliges taking #243 too. Single-entry lookup works here; revisit only if a real multi-entry case appears |
| `8953ea8f` | #241 | **declined** | claude.ai session key path for official limits. Stores a **full account session cookie as plaintext JSON** in Application Support (0600); upstream states the tradeoff openly. 0600 does not protect against other processes running as the user, backups, or cloud sync, and a `sessionKey` is not a scoped limits token. The Keychain-prompt friction it solves is real, but the answer here is a stable signing identity (`create-signing-cert.sh`), not a credential at rest. **Do not revisit without that security argument being addressed** |
| `3214f83c` | #228 | declined | Pick up an in-place Claude account switch on auto-poll. Touches the hardened OAuth path; only pays off if accounts are switched without restarting. Revisit if that becomes a real workflow |
| `60808c54` | #242 | skipped | Keep released Pokémon in the Pokédex. This fork has no release feature, so it is a feature import, not a missing fix. **If ever imported**: it appends a dex row without `monID`, and `restoredPartyFromCatchLog` resurrects exactly those rows, so the restore must also skip `releasedAt != nil` or every released mon returns to the PC on next load |
| `ff54b44e` | #238 | skipped | Kiro CLI 2.20+ JSONL sessions. Kiro is not installed on this fork's machines |
| `b833f127` | #214 | skipped | oh-my-pi (omp) usage provider. Not installed |
| `4fe965ee` | #197 | pending | Cursor usage from the dashboard API when local `tokenCount` is zero. Genuinely wanted (Cursor is in use), but adds a 464-line `CursorUsageAPI.swift` with a new outbound credential surface, so it goes in as its own reviewed change rather than a cherry-pick |
| `d6fb966a` | #212 | pending | Animation quality picker for the menu bar sprite and floating pet. Reasonable value; take after #22 settles, since it touches four files battles also changed |
| `77e159ce` | #234 | declined | German UI language. 549 lines of churn in the most-diverged file (`Localization.swift`: moves, TMs, battles), and it creates a standing tax where every new fork string needs a German value. Standing decision: no machine-translated fork strings. Revisit only if someone actually needs German |
| `a69444c8` | #239 | declined | Upstream readme edits. The READMEs here have diverged (moves, TMs, battles); apply anything relevant by hand instead |
| `8a20c3a4` | #247 | **ported** | Why Claude's `refreshToken` must not be used for renewal: it rotates, so refreshing from here would leave Claude Code holding a dead token and force the user to log in again. Pure docs upstream; ported the rule into this fork's defect log, minus its framing of the session key (#241) as the alternative, which this fork declined |
