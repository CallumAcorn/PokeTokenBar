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
| `4fe965ee` | #197 | declined | Cursor usage from the dashboard API. Callum's decision, 2026-10-21: declined; adds an outbound credential surface for a usage source |
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
| `b0c6074f` | #244 | declined | Difficulty multipliers. Callum's decision, 2026-10-21: not wanted |
| `5963293b` | #287 | declined | Fix for #244 difficulty changes. Declined with #244 |
| `d4d34e7d` | #284 | declined | Removes the floating-pet toggle #244 added. Declined with #244 |
| `014fcb28` | #352 | declined | First-run egg hint follows growth difficulty. Declined with #244 |
| `2fab082c` | #290 | deferred | Complete selected-language localisation, 835 lines. Heavy churn in the most-diverged file |
| `10d1a07c` | #288 | **ported** | Unown letter forms. Ported as part of the generic forms implementation (04b12da9), not replayed; see `pokemon-forms.md` |
| `4bfae978` | — | **ported** | Collected appearances chosen separately, shine per appearance. Fork Pokédex picker; pin takes only a collected form |
| `0912c68c` | #270 | **ported** | Monthly day-by-day usage trend, with the shared `ProviderEnrichment.local`. omp and Aside dropped (not in the fork); desktop chat adds its ledger to the month |
| `78595ed8` | #332 | **ported** | Usage recap for any week, month or year. Release filter dropped; Unown parts wired in with the forms port |
| `2eec9afa` | #298 | **ported** | Pace marker on quota bars. Ported; hint string reworded without an em dash |
| `68deb094` | #349 | **ported** | Colour quota bars by pace. Ported |
| `b32717fb` | — | **ported** | Colour menu-bar limit percentages like the gauges. Adapted to the fork's single Claude account; no Cursor, no menu tooltip |
| `2ecf7d2f` | #246 | **ported** | Ready egg hatches without racing the prefetch. The waiting-for-network hint is left out |
| `2e8efddf` | #328 | deferred | Bulk Rare Candy use with growth previews. Touches the candy code fixed in #29 |
| `13e3bf2a` | — | **ported** | Local save auto-backup and corruption recovery. Every restore path goes through `SaveTransfer.sanitized`; adapted to `party` |
| `ae7bd9d3` | — | **ported** | Search, sort and filters for the Pokédex and catch log. Fork-adapted store helpers (`isTrainingLogEntry`, `dexUnlocked`) |
| `f0ef5ff3` | — | deferred | Colour dex numbers by rarity |
| `279e112d` | #370 | deferred | Larger text and sprites in a 4x4 collection grid |
| `d44329bb` | — | deferred | Fixed-height Home tab with a reserved scroll area |
| `746d8384` | #356 | deferred | Korean particles matched to the name |
| `c9514926` | #291 | **skipped** | Tell shoppers what a released Pokémon keeps. Needs a release feature the fork does not have |
| `b4ff5de9` | — | **skipped** | Protect legendaries from egg discard. Not applicable: the fork benches the companion to the PC when an egg is bought, it never discards |
| `fe51577e` | #351 | deferred | Show real shiny odds in hatch notifications |
| `184c5f41` | #282 | **ported** | Lazy catch-log rows. The image-cache half is left out |
| `087fd0f7` | #285 | deferred | Dex sprite animation consistency |
| `fd008e53` | #286 | **ported** | Quota graph fill matches the remaining display mode. Ported with the pace batch (2026-10-21) |
| `bb92bd2a` | #292 | **ported** | Align quota percentages. Ported with the pace batch |
| `a8b3ba82` | #293 | deferred | Display costs as plain dollars |
| `1a8a7252` | #295 | **skipped** | Avoid English flashes loading names. Changes a view that only exists after deferred #290 (`2fab082c`) |
| `1c695c7d` | #311 | deferred | Show a skipped release in Settings. Safe for update pinning, but conflicts across four forked UI files |
| `a94b3dae` | — | **ported** | Stop unchanged status lines filling the log. Applied to the fork's own status lines (limits, codex, provider status, desktop scan) |
| `5f6a4f0a` | — | **ported** | Log each unpriced model once, on the fork's $0 fallback (the fork has no Unavailable cost state) |
| `8b2dd955` | — | **ported** | Prefer Claude Code's reported cost-state over the price table. One measured session: table $6.95, reported $6.13. Added a $100,000-per-model sanity cap and a Claude parser version so old cache blobs re-read |
| `906bbb97` | #401 | taken | Resume suspended polling when `screensDidWake` is missed. Session-key test stubs (declined `8953ea8f`, claude.ai session key) dropped from the test file |
| `a8dd8063` | #377 | **ported** | Retain idle-day history. Taken without its monthly-trend series and recap button, which belong to deferred #270/#332; its rendering test dropped for the same reason |
| `9c9c805d` | #424 | **ported** | Dedupe repeated species in saved chains. Applied in `sanitizedMon` so every PC member is covered, not one `active`; regression test fails with the dedupe removed |
| `fad8f1af` | #422 | **ported** | Shedinja HP 1. Added to `StatCalc` for the PC detail only; battle HP stays server-derived |
| `711fca75` | #418 | taken | Formatter precision from the rounded value |
| `11197c80` | #416 | taken | Antigravity refresh of an expired cached token on the auto poll; in memory only, no Keychain write. Upstream's test needs injection the fork's cache lacks; Keychain-gate tests still cover the auto path |
| `2745fde2` | #414 | taken | Skip Antigravity buckets without `remainingFraction` |
| `e2d01aff` | #393 | **ported** | Scroll-wheel paging, applied to the fork's Pokédex grid (git anchored it on the PC grid) |
| `481ad3a9` | #389 | taken | Fit wide sprites to the menu bar height |
| `1e5603a9` | #384 | **ported** | Rows for Sonnet 5.5, GPT-6 Sol, GPT-6.1 Sol, GPT-6 Luna. The fork has no long-context pricing to extend |
| `be9cbc7f` | #373 | **ported** | Right-click menu, all local actions. Adapted: fork cost type, dex item opens Collection, new hide-pet string |
| `14e9a6c7` | #371 | **ported** | Multi-buy on the fork's `shopPrice`. Quantity capped by balance ÷ price, so `price × count` cannot overflow; test added |
| `8771013b` | #366 | taken | Shop shortcut from the empty Bag |
| `4cab9f00` | #365 | taken | Promote compact units at rounding boundaries |
| `8804232c` | #364 | taken | Provider contribution guides; the link to upstream's issue tracker removed |
| `231002d2` | #410 | taken | Warning threshold stays below critical. Cursor test from the same file dropped |
| `abe0b9a0` | #392 | **ported** | Hover for exact growth progress, on the fork's `trainingMon` |
| `a2ec3649` | #321 | **ported** | Cooldown only after a validated release, plus an in-flight guard. Upstream's tag check rejected `-hardened.N`, which would have silenced every fork update; the fork accepts its own scheme. Upstream also committed a `default.profraw`, removed |
| `40b506ee` | #403 | deferred | Kimi Code provider. Built on omp/Aside (skipped) and upstream's parser-version cache, 17 conflicts in the cache alone |
| `26efe4ec` | #394 | **ported** | Open a Pokédex entry by clicking a sprite, through a popover navigation hook; checked in the running app |
| `11eebe62` | #402 | **ported** | Keep recent providers' tabs across calendar resets. Applies now the fork has `ProviderEnrichment.local` |
| `656d603f` | #380 | **ported** | 22pt pager hit area without moving the footer; checked in the running app (7 and 10pt from the glyph page, 12pt do not) |
| `9be4ea95` | #372 | deferred | Russian UI. Every string gains a column and the fork's own strings need translations |
| `0269dad7` | #395 | **ported** | Daily trend by calendar month. Taken with #270 |
| `5afeb2a5` | #368 | **ported** | Recap chart tooltips. Taken with #332 |
| `e21fb015` | #367 | **ported** | Return to the current period from recaps. Taken with #332 |
| `142fa08d` | #348 | **ported** | Stack daily trend bars by provider. Cost via `TokenFormatter.cost` with the fork's `> 0` rule |
| `f2d5c3e9` | #426 | **skipped** | Cursor pagination. Depends on the Cursor dashboard API (pending `4fe965ee`) |
| `5ee12eee` | #412 | **skipped** | Cursor auth-expired notice. Same dependency |
| `7a5742f5` | #408 | **skipped** | Cursor limit bars. Same dependency |
| `e2f8bcca` | #420 | **ported** | Hide a disguised Ditto's shiny in save snapshots. Covered by the backup port (`displaysShiny`) |
| `1a710185` | #420 | **skipped** | Empty duplicate of `e2f8bcca` |
| `e772e1f8` | #398 | **skipped** | Difficulty slider labels. The fork has no difficulty settings |
| `46d5d913` | #391 | **skipped** | Game-coloured type badges. The fork already has them; the rest is a header reshuffle |
| `fc66c1e1` | #390 | **skipped** | Shiny filter button size. The fork has no shiny filter |
| `cf91ddcb` | #383 | **skipped** | Kiro tool/thinking estimates. Changes the Kiro JSONL reader the fork skipped (`ff54b44e`) |
| `eb6ea0cc` | #378 | **skipped** | Ditto repeat boost. The fork has no repeat growth boost |
| `c328d5ce` | #429 | **skipped** | Hide redundant individual selector. The fork has no such picker |
| `b886b7a3` | #406 | **skipped** | Portuguese "evolução". Already correct in the fork |
| `5214b04f` | #374 | **declined** | Always show shiny sprites in the Pokédex grid. Changes the fork's tap-to-reveal behaviour, which the README documents |
| `3b2e4c09` | #427 | **declined** | Upstream's PR workflow: agent skill folders, `AGENTS.md` edits, PR-format checker. Their contribution process, not this fork's |
| `498bdbc6` | #400 | **declined** | Universal binary. The fork ships no binaries; everyone builds natively from source |
| `d8887937` | #375 | **ported** | Rare Candy re-granted on reset-time jitter. The fork had the same bug (string comparison in its reset re-arm); now a window must move 30 min (five-hour) or 24 h (weekly) |
| `a4d17d58` | #435 | **skipped** | Return to the viewed Pokédex page after Back. Not applicable: the fork's grid keeps its page across Back, and catch-log rows do not open a detail page |
| `04b12da9` | #376 | **ported** | Alternate forms for gen 1-5 species. Fork-native: collection from catch log + party, `FormNameStore` names instead of the general name layer (`2fab082c`). See `pokemon-forms.md` |
| `fd12f005` | #446 | **ported** | Collapse backup history in Settings by default. Fork CI file kept |
| `dc6de418` | — | **ported** | Sonnet 5.5 cache read $0.10, Antigravity keeping its refresh credential after transient failures, the form on backup thumbnails and the "Data uses the default form" note |
| `594be29c` | — | **declined** | Upstream's release notes since 2.5.5 |
| `17cf2bfb` | — | **skipped** | Pixel-density fix for a form-caption rendering test the fork does not carry |
| `2c0212b5` | — | **declined** | Upstream README image labels |
| `4617c8ab` | — | **declined** | Upstream release images |
| `b716054e` | — | **skipped** | Session-key settings reveal. The session-key feature was declined (`8953ea8f`) |
| `77f789d7` | — | **declined** | Upstream's version bump to 2.5.6 |
| `2f2fb321` | #447 | **ported** | Recover sprite animations after failed downloads. Retry wait capped at 5 minutes instead of 30 seconds, and the menu bar cancels stale loops |
| `d82867bb` | #448 | **skipped** | Empty Settings windows. Already fixed here by #44 without upstream's private `_EmptyScene` API |
