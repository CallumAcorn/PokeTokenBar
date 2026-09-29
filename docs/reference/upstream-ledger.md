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
| `deferred` | Wanted in principle, but it conflicts with how far this fork has diverged, so taking it means a deliberate port that could disturb existing behaviour. Not a decline: revisit by porting, not cherry-picking |

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
| `d6fb966a` | #212 | **ported** | Animation quality picker (Power saver / Balanced / Smooth). Taken as the prerequisite for #250, which carries the `AnimationQuality` enum in its own diff and cannot apply without it. Cherry-pick conflicted in 8 files: the READMEs (kept ours, took only the animation-quality bullet; their representative bullet duplicates one we already have), and `PokeTokenBarApp`/`CompanionView`, which read upstream's `representativeSubject`. This fork reimplemented representative on `dexUnlocked`, so our identity source was kept and only the fps-floor wiring taken: floor added to `frameTaskID`/`menuSpriteKey` and `store.animationQuality` observed, with our `facing` axis preserved alongside |
| `77e159ce` | #234 | declined | German UI language. 549 lines of churn in the most-diverged file (`Localization.swift`: moves, TMs, battles), and it creates a standing tax where every new fork string needs a German value. Standing decision: no machine-translated fork strings. Revisit only if someone actually needs German |
| `a69444c8` | #239 | declined | Upstream readme edits. The READMEs here have diverged (moves, TMs, battles); apply anything relevant by hand instead |
| `8a20c3a4` | #247 | **ported** | Why Claude's `refreshToken` must not be used for renewal: it rotates, so refreshing from here would leave Claude Code holding a dead token and force the user to log in again. Pure docs upstream; ported the rule into this fork's defect log, minus its framing of the session key (#241) as the alternative, which this fork declined |
| `edc3b3ca` | #255 | taken | Swap menu bar sprite frames through `spriteLayer.contents` instead of `button.image`. Real battery win on an always-visible animation and provider-independent: the assignment forced a full button redraw including the two-line title, measured 2.00ms/frame to 0.27ms. Only the defect-log entry conflicted, and our side was empty there |
| `cb4fba7d` | #256 | taken | Drop stale `ccusage` references from runtime comments. We still carried three in `UsageStore.swift`, and the release doc-check greps for exactly that string |
| `37763d3c` | #250 | taken | Keep the menu bar animating in Low Power Mode, capped at Power saver. Applied cleanly once #212 was in place, which confirmed the dependency |
| `e6d99a87` | #225 | skipped | Attribute Pi/OMP usage to the real model, per-model day breakdown. Neither Pi Agent nor oh-my-pi is installed on this fork's machines |
| `ce65fde8` | #245 | skipped | Align Antigravity limits stale UI with Claude. Antigravity is not installed |
| `5f1ef524` | #262 | skipped | Resolve the codex binary bundled inside `ChatGPT.app`. Codex is present here but `ChatGPT.app` is not, so this specific resolution path never applies |
| `56a35471` | #261 | skipped | Keep shop egg cards visible during the egg stage. **Already reimplemented independently** in PR #25, which always shows the eggs group and swaps the buy cards for an incubating message. Recorded so this is never taken on top of our own version |
| `77bc9b8b` | — | declined | Upstream's 2.5.3 version bump. Meaningless under this fork's scheme, where the core tracks the upstream base and `-hardened.N` counts our builds |
| `d4d07c11` | — | declined | Screenshots and README tour rows for the session key (declined as #241), the per-model breakdown (skipped) and animation quality. Our READMEs have diverged; the animation-quality row was taken by hand as part of #212 instead |
| `b34673aa` | #252 | taken | Immediate refresh on network reconnection. `NWPathMonitor`, no entitlements, and it debounces with a cooldown. Checked against the 429 backoff we just added: it calls the automatic refresh path, which already skips the Claude fetch while a backoff is live, so it cannot worsen rate limiting |
| `f2fe5aca` | #263 | taken | Absolute reset time next to limit countdowns. Pairs with the Rare Candy fix, which now relies on those same reset times, so surfacing them closes the loop for the user |
| `cd3125ab` | #267 | taken | Floating pet size ceiling 192px to 384px. Their test covers panel geometry only, not energy: a 384px animated sprite costs meaningfully more than 192px. Acceptable because the size is opt-in and we now have the animation-quality setting (#212) and the layer-swap perf work (#255) |
| `232108cf` | #279 | **ported** | Taken as the `claude-fable-5-1` price row only. Without it the `fable` family fallback applies Fable 5's $1.00 cache read instead of $0.25 and **overstates cost 4x**; verified by injection. **The other half of this commit is NOT taken and still needs a decision**: `LocalUsageReader` +77 changes how Codex total-only turns are counted (#278), which is usage attribution rather than pricing. Codex is present on this machine, so it may be wanted |
| `b6bf676f` | #264 | **declined** | Persistent individual values plus a Pokédex detail page, 1651 insertions across 16 files. **This fork already has IVs** (`MonState.ivs`/`evs`, `StatCalc`, clamped in `sanitizedMon`) built independently, so taking this would run a second parallel implementation into a model that already has one. Same structural fork as #158 and #211 at roughly ten times the size. If the Pokédex detail page is ever wanted, port that piece alone against our model |
| `78980651` | #275 | **declined** | Ambient Keychain help popover. Its explanation is correct and independently confirms our own root-cause diagnosis, but the remedy it offers is the session key declined as #241: the help body's payoff is "register a session key", and the button is gated on `store.sessionKeyConfigured`, which does not exist here. Taking the meaningful part would steer users toward a full account cookie stored in plaintext. The safe half (explaining why the grant dies) already shipped in our own revocation notice, which offers re-authorising instead |
| `a9107676` | #333 | taken | Hide providers with zero-token synthetic activity. Applied cleanly |
| `878a0be2` | #307 | **ported** | Clamp extra-provider token counts. Ported as the `LocalAdditionalUsageProvider.intValue` ceiling only: that separate copy had no upper bound, and `parseCursorBubble`'s `input + output` trapped on a corrupt Cursor record (verified SIGTRAP). The Cursor dashboard half targets `CursorUsageAPI.swift`, which this fork does not have (#197 pending) |
| `1ef19797` | #304 | **ported** | Claude 5 price rows, without #289's fallback removal. Sonnet 5 had been billed at Sonnet 4's fallback rate, 1.5x high |
| `832154af` | — | **ported** | Opus 5.5 price row. The fallback billed it at Opus 5's rate: 25% high on input, output and cache writes, 2.5x high on cache reads |
| `29a4e2d2` | #309 | **ported** | gemini-2.5-flash-lite price row. Pricing only |
| `d6d24a04` | — | **ported** | Stop tests rewriting the user's files. **Measured on this machine**: one suite run changed the real `usage-cache.json` 726,929 to 763,881 bytes. Ported as `AppEnv.persistsToUserLocation` gating the usage cache; no state file changes after |
| `671c1ece` | — | **ported** | Stop tests calling live limits endpoints. About ten tests built a `UsageStore` with the real providers, so with a live Keychain grant they called Anthropic with the user's token. Ported as `AppEnv.allowsLiveLimitsFetch` on the Claude and Antigravity fetches. The two Keychain-discipline tests now run against a stubbed Keychain instead of the real one |
| `e5b48004` | #327 | **declined** | Track several Claude accounts, 3,419 lines. Built on the session key declined as #241 (25 references). Would reintroduce a full account cookie stored in plaintext |
| `eed5b735` | — | **declined** | Per-account session key. Same reason as #241 |
| `c9c016d0` | #280 | skipped | Prioritise user account over MCP placeholders. Built on the multi-account Keychain enumeration declined as #232; this fork's single-entry lookup is unaffected |
| `e76a8e01` | #344 | skipped | Keep forked usage with its original account. Depends on multi-account (#327, declined) |
| `5bd8d435` | #283 | skipped | Aside usage provider. Not installed, and a new provider adds parsing of untrusted files for no benefit |
| `aaef5db0` | #274 | skipped | Antigravity nested token file and OAuth refresh. Antigravity not installed |
| `87c67927` | #325 | skipped | Antigravity CLI/IDE token auto-detect. Not installed |
| `641e3e80` | #323 | skipped | Localise Antigravity group names. Not installed |
| `ab6c768d` | #276 | skipped | oh-my-pi per-model usage. Not installed |
| `8c08e013` | #369 | skipped | Discover the codex bundle inside ChatGPT.app. ChatGPT.app not installed |
| `3ea40afc` | #363 | skipped | OpenCode v2 sessions. Not installed |
| `777ee274` | — | skipped | Cursor remaining included usage from the dashboard. Depends on the Cursor dashboard API (#197, still pending) |
| `e94da861` | #334 | skipped | Re-arm Rare Candy when a limit window resets. **This fork already has it**, independently, as PR #29: the same design, keeping `resets_at` out of the key and re-arming when the recorded value changes. Upstream's also covers Codex windows; Codex limits do not load on this machine, so no loss |
| `32725093` | #302 | skipped | Re-read the Keychain on limit refresh. This fork already bypasses the token cache on manual refresh. The remainder is the floating-pet footer toggle, tied to the difficulty chain |
| `09fd6003` | — | declined | Upstream 2.5.4 version bump. Meaningless under this fork's versioning |
| `42df4e61` | — | declined | Upstream 2.5.5 version bump. Same |
| `065b2e18` | #297 | declined | Upstream release tour and screenshots. READMEs have diverged |
| `b63fce25` | — | declined | Upstream screenshots and feature guides. Same |
| `5e08e6fe` | #296 | declined | Require release notes and contributor attribution. Rewrites `release.sh`, which this fork has heavily reworked (source-only releases, asset waivers, `-hardened` versioning) |
| `dec297a5` | #254 | declined | 2x growth on repeat hatches. Changes the balance of an existing feature |
| `69ff39bb` | #289 | declined | Distinguish estimated from unavailable cost by removing the model-family price fallback. Would turn every unpriced model to 'Unavailable'; this fork instead adds explicit rows. 626 lines across 28 files |
| `b0c6074f` | #244 | deferred | Difficulty multipliers (growth and shop-price slider, default unchanged). Changes shop and growth code paths; awaiting the maintainer's call |
| `5963293b` | #287 | deferred | Fix for #244: difficulty changes advancing earned progress. Take with #244 |
| `d4d34e7d` | #284 | deferred | Removes the floating-pet toggle #244 added. Take with #244 |
| `014fcb28` | #352 | deferred | First-run egg hint follows growth difficulty. Depends on #244 |
| `2fab082c` | #290 | deferred | Complete selected-language localisation, 835 lines. Heavy churn in the most-diverged file |
| `10d1a07c` | #288 | deferred | Collect all Unown letter forms, 1,587 lines. Normalises its new state at the save boundary, but builds on the representative pin this fork reimplemented |
| `4bfae978` | — | deferred | Select collected appearances separately. Builds on #288 |
| `0912c68c` | #270 | deferred | Monthly day-by-day usage trend, 1,022 lines |
| `78595ed8` | #332 | deferred | Usage recap for any week, month or year, 1,136 lines |
| `2eec9afa` | #298 | deferred | Pace marker on quota bars |
| `68deb094` | #349 | deferred | Colour quota bars by pace. Builds on #298 |
| `b32717fb` | — | deferred | Colour menu-bar limit percentages like the gauges |
| `2ecf7d2f` | #246 | deferred | Explain delayed egg hatches and harden retry state |
| `2e8efddf` | #328 | deferred | Bulk Rare Candy use with growth previews. Touches the candy code fixed in #29 |
| `13e3bf2a` | — | deferred | Local save auto-backup and corruption recovery, 776 lines. Changes the load path; worth doing as its own reviewed change |
| `ae7bd9d3` | — | deferred | Search, sort and filters for the Pokédex and catch log, 775 lines |
| `f0ef5ff3` | — | deferred | Colour dex numbers by rarity |
| `279e112d` | #370 | deferred | Larger text and sprites in a 4x4 collection grid |
| `d44329bb` | — | deferred | Fixed-height Home tab with a reserved scroll area |
| `746d8384` | #356 | deferred | Korean particles matched to the name |
| `c9514926` | #291 | deferred | Tell shoppers what a released Pokémon keeps. Build fails here: depends on the release feature this fork lacks |
| `b4ff5de9` | — | deferred | **Protect legendary companions from accidental egg discard.** The most valuable deferral: it prevents losing a legendary. Changes the egg-purchase flow, so it wants a deliberate port |
| `fe51577e` | #351 | deferred | Show real shiny odds in hatch notifications |
| `184c5f41` | #282 | deferred | Avoid UI stalls opening large catch logs |
| `087fd0f7` | #285 | deferred | Dex sprite animation consistency |
| `fd008e53` | #286 | deferred | Quota graph fill matches remaining display mode |
| `bb92bd2a` | #292 | deferred | Align quota percentages |
| `a8b3ba82` | #293 | deferred | Display costs as plain dollars |
| `1a8a7252` | #295 | deferred | Avoid English flashes loading Pokémon names |
| `1c695c7d` | #311 | deferred | Show a skipped release in Settings. Safe for update pinning, but conflicts across four forked UI files |
| `a94b3dae` | — | deferred | Stop unchanged status lines filling the log |
| `5f6a4f0a` | — | deferred | Log each unpriced model once |
| `8b2dd955` | — | deferred | Prefer reported Claude cost-state over the price-table estimate |
