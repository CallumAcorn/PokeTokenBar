# Hardened cask for this fork. Copy into your own Homebrew tap.
#
# TEMPLATE ONLY. This fork currently publishes source-only releases (see INSTALL.md), so the
# release zip this cask points at does not exist and the sha256 below is a placeholder. It is kept
# so that, if binaries are ever published, the cask starts from the hardened shape.
#
# The token is deliberately NOT upstream's `poke-token-bar`. Sharing it meant
# `brew upgrade --cask poke-token-bar` could match an upstream install and pull
# their build instead of this one, which is the opposite of what a fork user
# wants. A distinct token makes the two impossible to confuse.
#
# Two deliberate differences from the upstream cask:
#
#   1. `sha256` is pinned to the release artefact instead of `:no_check`.
#      Upstream ships `sha256 :no_check` against a GitHub release URL. Release
#      assets are mutable — they can be deleted and re-uploaded under the same
#      tag — so `:no_check` means brew installs whatever bytes are served at that
#      URL at that moment, with no way to notice a substitution. `release.sh`
#      rewrites the value below on every release; a release that cannot produce a
#      hash does not ship.
#
#   2. There is no `postflight` running `xattr -cr`.
#      That call strips com.apple.quarantine before first launch, so Gatekeeper
#      never assesses the app at all. It is how an un-notarised build is made to
#      launch silently. This fork keeps quarantine intact: because the app is
#      signed with a self-signed certificate rather than a Developer ID, macOS
#      will refuse the first launch and you must right-click → Open once, or run
#      `xattr -d com.apple.quarantine` yourself. That is a conscious, auditable
#      decision by the person installing it, not something the installer does on
#      their behalf.
#
# Verify before you trust:
#   shasum -a 256 "$(brew --cache)/downloads/"*poke-token-bar-hardened*
#   gh attestation verify PokeTokenBar-ci --repo CallumAcorn/PokeTokenBar

cask "poke-token-bar-hardened" do
  version "2.5.1"
  # Replaced by scripts/release.sh at publish time. Never set this to :no_check.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/CallumAcorn/PokeTokenBar/releases/download/v#{version}/PokeTokenBar.zip"
  name "PokeTokenBar"
  desc "Menu bar app turning AI coding token usage into a growing Pokemon"
  homepage "https://github.com/CallumAcorn/PokeTokenBar"

  depends_on macos: ">= :sonoma"

  app "PokeTokenBar.app"

  caveats <<~EOS
    PokeTokenBar is signed with a self-signed certificate and is not notarised by
    Apple, so Gatekeeper will block the first launch. This cask deliberately does
    not strip the quarantine attribute for you.

    To open it once you have decided you trust it:
      right-click PokeTokenBar.app in /Applications, choose Open, then confirm.

    The app reads local AI CLI usage logs. To show official limits it also reads the
    Claude Code credential; that is on by default. Turn it off with Settings →
    Advanced → "Disable credential access". See SECURITY.md for the full data map.
  EOS

  zap trash: [
    "~/Library/Application Support/PokeTokenBar",
    "~/Library/Preferences/io.github.chattymin.poketokenbar.plist",
    "~/Library/Logs/PokeTokenBar.log",
    "~/Library/Logs/PokeTokenBar.old.log",
    "~/Library/Logs/PokeTokenBar.crash.log",
    "~/Library/Logs/PokeTokenBar.running",
  ]
end
