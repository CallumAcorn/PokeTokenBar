# Installing this fork

This is a security-hardened fork of [chattymin/PokeTokenBar](https://github.com/chattymin/PokeTokenBar).
The upstream project is well built and carries no malware. This fork changes how much the app can
reach by default, and how you can verify what you are running.

If you were sent here, read [What it does by default](#what-it-does-by-default) before installing.
Two behaviours differ from upstream, and the Keychain grant needs one deliberate click.

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
falling back to ad-hoc signing. The hardened runtime is applied either way, so this is fine.

**One caveat if you rebuild often.** Ad-hoc signing changes the binary's code-signature hash on
every build, which invalidates the macOS Keychain "Always Allow" grant. The app then falls back to
needing the refresh button until you grant access again. `scripts/create-signing-cert.sh` fixes
that by creating a stable identity, but it also installs a self-signed certificate as a
code-signing **trust root** in your login keychain, which is a real and permanent expansion of
what your Mac trusts. Install it once and rarely rebuild: skip the script. Rebuild regularly and
want limits to keep working without re-granting: run it, knowing that trade-off.

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

Two defaults differ from upstream, plus the Keychain grant described first. All are visible
in `~/Library/Logs/PokeTokenBar.log` shortly after launch.

**Official Claude limits need one grant.** On first use, press the refresh button on the limits
row and choose **Always Allow** at the macOS Keychain prompt. Automatic refresh will not read the
Keychain until a silent read has been proven to work, so without that one grant the limits row
stays stale and no background poll will ever prompt you. Choosing "Allow" rather than "Always
Allow" leaves it needing the button each time.

To switch credential reading off entirely: Settings → Advanced → **Disable credential access** on.
Log line while off:

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

## Updating

The app tells you when a new version exists but **cannot install it** — this fork publishes
tag-only releases with no downloadable build. Press "How to update" on the banner and run:

```
cd ~/Code/PokeTokenBar
git pull
./scripts/build-app.sh
```

Versions here look like `2.5.1-hardened.1`. The suffix exists because upstream and this fork would
otherwise ship different code under the same version string.

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

Four things make that conversation easier:

- The app reads **token counters only**. Prompt and response content is never parsed, stored or
  transmitted. [SECURITY.md](SECURITY.md) lists every path it touches.
- It talks to **ten fixed hosts**, none of which carry your usage, prompts or project paths. The
  only requests carrying anything of yours are the official-limit calls, which go to Anthropic and
  Google, the parties that issued those tokens, and can be switched off entirely in Settings.
- Trading and battles add **one more host, and only if you configure it**: a server you run
  yourself. Trading sends one Pokémon; a battle sends a roster of up to six as primitives (species,
  level, nature, ability, IVs, EVs, moves) plus each move you choose. Both send a display name you
  type and a random client id. No usage data and no credential. Leave the field empty and both
  features are inert.
- It registers the `poketokenbar://` URL scheme for trade and battle invites. Any web page can open
  such a link, so the app names the server and asks before connecting to it.

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
