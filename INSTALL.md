# Installing this fork

This is a security-hardened fork of [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar).
The upstream project is well built and carries no malware. This fork changes how much the app can
reach by default, and how you can verify what you are running.

If you were sent here, read [What it does by default](#what-it-does-by-default) before installing.
Three behaviours differ from upstream and one of them will look like a missing feature.

## There is no download, on purpose

There is no release zip and no Homebrew cask for this fork. You build it from source.

That is not laziness. A downloaded build would be self-signed and not notarised by Apple, so
macOS would refuse to open it and you would have to strip the quarantine attribute by hand.
Telling people to bypass Gatekeeper is exactly the pattern this fork removed from the upstream
cask, and it is not something to put in an instruction list. Building locally sidesteps it
entirely: a binary you compiled has no quarantine attribute, so it just runs.

You also get the thing a signature cannot give you, which is the ability to read the code you are
about to run.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon or Intel
- Xcode 16 or later, for the Swift 6 toolchain. `xcode-select --install` is not enough; you need
  full Xcode from the App Store
- git

Check your toolchain before starting:

```
swift --version
```

Swift 6.0 or later. If that command fails or reports 5.x, install Xcode and run
`sudo xcode-select -s /Applications/Xcode.app`.

## Install

```
git clone https://github.com/CallumAcorn/PokeTokenBar.git
cd PokeTokenBar
./scripts/test-gate.sh
./scripts/verify-hardening.sh
./scripts/build-app.sh
open /Applications/PokeTokenBar.app
```

What each step does:

| Step | What it does |
|---|---|
| `test-gate.sh` | Runs the full test suite and enforces a coverage floor |
| `verify-hardening.sh` | Asserts the security properties below against a real build. Installs nothing |
| `build-app.sh` | Builds, signs with the hardened runtime, and copies to `/Applications` |

Budget around 10 minutes in total on a first run. The cold release build of roughly 26k lines of
Swift is the slow part; later builds are incremental and take seconds. Both verification steps are
optional if you just want the app, but they are the point of building from source, so run them at
least once.

`build-app.sh` will print that no `PokeTokenBar Local` signing identity was found and that it is
falling back to ad-hoc signing. **That is the expected and recommended outcome.** The hardened
runtime is applied either way. Do not run `scripts/create-signing-cert.sh` unless you have a
specific reason: it installs a self-signed certificate as a code-signing **trust root** in your
login keychain, and the only thing it buys you is avoiding a repeat Keychain prompt when the app
reads your Claude credential, which is off by default here anyway.

`build-app.sh` quits any running copy and replaces `/Applications/PokeTokenBar.app`. It touches
nothing else.

## Verify your install

```
codesign -d --verbose=2 /Applications/PokeTokenBar.app 2>&1 | grep flags
launchctl list | grep -i poketokenbar
ls /Applications/PokeTokenBar.app/Contents/Library/LaunchAgents/
```

Expected:

- flags include `runtime`, for example `flags=0x10002(adhoc,runtime)`
- **no output** from `launchctl`, meaning nothing has been registered to start at login
- two plists present, both inactive until you opt in

## What it does by default

Three defaults differ from upstream. All three are visible in
`~/Library/Logs/PokeTokenBar.log` shortly after launch.

**Official Claude limits are hidden.** The app does not read your Claude credential unless you
ask it to, so the "Limits (official)" row is absent. This is the change most likely to be mistaken
for a bug. Upstream reads the credential on first launch; this fork does not. To turn it on:
Settings → Advanced → switch **Disable credential access** off, then press the refresh button.
macOS will prompt for Keychain access once. Log line while off:

```
claude limits skipped: keychain access disabled
```

**Tool paths are not resolved through your shell.** Upstream spawns `$SHELL -ilc`, which executes
your entire `.zshrc` inside the app, to discover where your CLI tools live. That is off here. The
app still finds tools in Homebrew, mise, asdf, Volta, Bun, npm and `~/.local/bin`. If one of your
tools lives somewhere else it will not be detected; turn shell resolution on in Settings →
Advanced, or point directly at the binary with a `<binary>Path` user default. Log line:

```
codex not in static paths and shell resolution is disabled — skipping shell spawn
```

**The app does not restart itself.** Upstream's login agent carries `KeepAlive`, so launchd
revives it after any non-zero exit. Here that is a separate opt-in switch, off by default.
"Launch at login" on its own only starts the app at login.

## First run

Expect a slow first scan. The app reads local usage logs from every AI CLI you have, and a large
`~/.cursor` directory can take a while on the first pass before it goes incremental. It appears in
the menu bar only, with no Dock icon. Watch `~/Library/Logs/PokeTokenBar.log` if it seems stuck.

## Uninstall

```
pkill -x PokeTokenBar
launchctl bootout gui/$(id -u)/io.github.chattymin.poketokenbar.login 2>/dev/null
launchctl bootout gui/$(id -u)/io.github.chattymin.poketokenbar.autorestart 2>/dev/null
rm -rf /Applications/PokeTokenBar.app ~/Library/Application\ Support/PokeTokenBar
rm -f ~/Library/Preferences/io.github.chattymin.poketokenbar.plist ~/Library/Logs/PokeTokenBar*
```

## If your Mac is managed by your employer

Read this part before installing on a work machine.

This app is **not notarised by Apple**. On a managed Mac that is a software-approval question for
whoever runs your fleet, not a personal choice, regardless of how the app behaves. Endpoint
security tooling may also take an interest in it: it runs continuously, reads several
credential-adjacent directories, and can register a launchd agent. None of that is malicious, and
all of it is documented in [SECURITY.md](SECURITY.md), but it is the shape that gets flagged.

Two things make that conversation easier:

- The app reads **token counters only**. Prompt and response content is never parsed, stored or
  transmitted. [SECURITY.md](SECURITY.md) lists every path it touches.
- It talks to **seven hosts**, none of which carry your usage, prompts or project paths. The only
  request carrying anything of yours is the optional Claude limits call, which goes to Anthropic,
  and it is off by default.

Ask first. Do not strip quarantine or disable protections to make it run.

## Where to look next

| Document | Contents |
|---|---|
| [SECURITY.md](SECURITY.md) | Every path read, all egress hosts, what the OAuth token is and is not, both launchd agents |
| [docs/reference/fork-hardening.md](docs/reference/fork-hardening.md) | Each change against the upstream behaviour it replaces |

## Credits and licence

Upstream is [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar) by Patrick Park
and contributors, MIT licensed. This fork keeps that licence and copyright.

Pokémon sprites are fetched at runtime from [PokéAPI](https://pokeapi.co/) and cached locally.
No Pokémon assets are bundled in this repository or in the built app. Pokémon and Pokémon
character names are trademarks of Nintendo, Creatures Inc. and GAME FREAK Inc. This project is
unofficial and not affiliated with them.
