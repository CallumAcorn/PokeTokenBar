# Security

PokeTokenBar is a menu bar app that reads local AI coding tool usage logs and draws a Pokémon
from them. That means it runs continuously, reads several credential-adjacent directories, and
talks to a handful of network hosts. This document says exactly what it does, so you can decide
whether you want it running rather than having to infer it from the source.

This is a hardened fork. Section [What this fork changes](#what-this-fork-changes) lists the
differences from upstream and why each one exists.

## Reporting a vulnerability

Open a private security advisory on this repository
(Security → Advisories → Report a vulnerability). Please do not open a public issue for anything
that would give someone else access to a user's machine or credentials.

## What the app reads

All of this is read locally. None of it is uploaded anywhere.

| Path | What is taken from it |
|---|---|
| `~/.claude/projects/**.jsonl` | `message.usage` token counters, model id, message and request ids, timestamps |
| `~/.codex/sessions/**` | `last_token_usage` turn deltas |
| `~/.gemini/tmp`, `~/.grok/sessions` | token counters |
| `~/.gemini/antigravity-cli/conversations` | token counters |
| `~/.copilot/session-store.db` | rows from `assistant_usage_events` |
| `~/Library/Application Support/Cursor/**/state.vscdb` | usage rows from `cursorDiskKV` |
| `~/Library/Application Support/kiro-cli/data.sqlite3` | conversation byte estimates |
| `~/.local/share/opencode`, `~/.hermes` | message rows |
| Keychain `Claude Code-credentials` or `~/.claude/.credentials.json` | OAuth access token, **only when enabled** |

**Prompt and response content is never read into memory.** The Claude parser filters to lines
containing `"usage"` and `"assistant"` and extracts only the numeric counters and identifiers.
Conversation text is not parsed, stored, or transmitted.

## Network egress

Seven hosts, and nothing else. There is no telemetry, no analytics, and no vendor server.

| Host | Purpose | Carries |
|---|---|---|
| `api.anthropic.com` | Official Claude 5h/weekly limits | Your OAuth bearer token |
| `api.github.com` | Update check | Nothing |
| `pokeapi.co`, `graphql.pokeapi.co` | Species and evolution data | Nothing |
| `raw.githubusercontent.com` | Sprite images | Nothing |
| `status.claude.com`, `status.openai.com` | Incident banner | Nothing |

The only outbound request carrying anything of yours is the Claude limits call, which goes to
Anthropic, the party that issued the token. It is off by default in this fork. The single `POST`
in the codebase is a GraphQL query to PokéAPI.

## Credentials

When you turn on official limits, the app reads your Claude OAuth access token and sends it as a
bearer token to `api.anthropic.com/api/oauth/usage`. You should understand three things about
this:

- The token is a **full-scope account credential**, not a read-only scoped token. Anthropic does
  not currently issue a narrower one for this purpose.
- It is held **in memory only**. The app creates no Keychain item of its own and writes the token
  to no file.
- The endpoint is **undocumented**. It can change or disappear without notice; the app treats
  failure as "hide the limits section" and carries on.

**Credential access is off by default in this fork.** Turn it on in Settings → Advanced by
switching "Disable credential access" off. While it is on, the app reads neither the Keychain nor
`~/.claude/.credentials.json`. Automatic polling never triggers a Keychain prompt; only the
explicit refresh button does.

## Persistence

"Launch at login" registers a launchd agent from inside the app bundle. This fork ships two, and
registers exactly one:

| Agent | Behaviour | Default |
|---|---|---|
| `io.github.chattymin.poketokenbar.login` | `RunAtLoad` only | Used when launch at login is on |
| `io.github.chattymin.poketokenbar.autorestart` | `RunAtLoad` + `KeepAlive` | Opt-in |

The second one restarts the app whenever it exits non-zero. That is genuine crash recovery, and
it is also the behaviour endpoint security tools watch for, so it is a separate switch rather
than something bundled into the login toggle.

To remove either by hand:

```
launchctl bootout gui/$(id -u)/io.github.chattymin.poketokenbar.login
launchctl bootout gui/$(id -u)/io.github.chattymin.poketokenbar.autorestart
```

## Process execution

The app spawns child processes in two places:

- `codex app-server`, to read official Codex limits over JSON-RPC. Only if you use Codex.
- Your login shell, to resolve tool paths that a GUI app cannot see. **Off by default in this
  fork**, because `$SHELL -ilc` executes your entire interactive profile inside the app. The
  static path list covers Homebrew, mise, asdf, Volta, Bun, npm and `~/.local/bin`, which is
  enough for most installs. Turn it on in Settings → Advanced if your tools live elsewhere, or
  set the `<binary>Path` user default to point straight at the binary.

When it is on, `$SHELL` is accepted only if `/etc/shells` lists it, falling back to `/bin/zsh`
otherwise. Arguments are always passed positionally, never interpolated into the script text.

## Verifying what you are running

The app is signed with a **self-signed certificate** and is **not notarised by Apple**. Gatekeeper
will therefore refuse the first launch, and the cask in `packaging/` deliberately does not strip
the quarantine attribute for you.

The strongest guarantee is to build it yourself:

```
git clone https://github.com/CallumAcorn/PokeTokenBar.git
cd PokeTokenBar
./scripts/test-gate.sh          # tests + coverage floor
./scripts/verify-hardening.sh   # asserts the security properties below
./scripts/build-app.sh          # builds, signs with hardened runtime, installs
```

If you install a published release instead, check it against the checksums and the CI provenance
attestation:

```
shasum -a 256 PokeTokenBar.zip            # compare against SHA256SUMS on the release
gh attestation verify PokeTokenBar-ci --repo CallumAcorn/PokeTokenBar
```

The attestation proves GitHub built the `PokeTokenBar-ci` binary from this repository at that tag.
It does **not** prove the separately uploaded, locally signed `PokeTokenBar.zip` matches, because a
signature made on a maintainer's Mac cannot be reproduced in CI. What it does give you is an
independent build to diff against. Building from source remains the only complete answer.

`scripts/verify-hardening.sh` asserts, against a real build:

- hardened runtime is applied, so library validation is on and dylib injection is refused
- no entitlements are granted, in particular nothing disabling library validation
- the default login agent carries no `KeepAlive`
- the cask pins a `sha256` and never runs `xattr`
- every GitHub Action is pinned to a commit SHA

## What this fork changes

See [`docs/reference/fork-hardening.md`](docs/reference/fork-hardening.md) for the full list with
rationale and the upstream behaviour each item replaces.
