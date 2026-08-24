#!/usr/bin/env bash
#
# upstream-status.sh — what actually needs a decision from upstream.
#
# GitHub's "N commits behind" is not usable here. Commits arrive by cherry-pick, which rewrites
# them into new SHAs, so upstream's originals stay "absent" forever even when fully merged.
# Measured once: the banner said 22 behind while 4 genuinely needed a decision.
#
# This subtracts two things from that number:
#   1. patch-equivalent commits — `git cherry` detects content already applied under a new SHA
#   2. commits recorded in docs/reference/upstream-ledger.md — including deliberate declines
#
# Anything left is UNREVIEWED: decide it, then add a ledger row so it never resurfaces.
#
# Usage:  ./scripts/upstream-status.sh [upstream-remote]
#
# `set -e` is off on purpose: "no outstanding commits" is a normal result reached through
# commands that legitimately return non-zero.
set -u
cd "$(dirname "$0")/.."

REMOTE="${1:-upstream}"
LEDGER="docs/reference/upstream-ledger.md"

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "✗ no '$REMOTE' remote. Add it:" >&2
  echo "    git remote add upstream https://github.com/chattymin/PokeTokenBar.git" >&2
  exit 1
fi

git fetch "$REMOTE" --quiet 2>/dev/null

applied=0; ledgered=0; unreviewed=0
unreviewed_list=""

# `git cherry` marks '-' for patch-equivalent (already applied) and '+' for outstanding.
while read -r sym sha; do
  [[ -z "${sha:-}" ]] && continue
  subject=$(git log -1 --format='%s' "$sha" 2>/dev/null)
  short=${sha:0:8}
  if [[ "$sym" == "-" ]]; then
    applied=$((applied + 1))
    continue
  fi
  # Comment lines and the fenced example do not count as ledger rows; a row starts with '| `sha`'.
  if grep -qE "^\|[[:space:]]*\`$short\`" "$LEDGER" 2>/dev/null; then
    disposition=$(grep -E "^\|[[:space:]]*\`$short\`" "$LEDGER" | awk -F'|' '{print $4}' | tr -d ' *')
    ledgered=$((ledgered + 1))
    printf '  %-10s %-9s %s\n' "$short" "$disposition" "${subject:0:56}"
    continue
  fi
  unreviewed=$((unreviewed + 1))
  unreviewed_list="$unreviewed_list$short|$subject"$'\n'
done < <(git cherry main "$REMOTE/main" 2>/dev/null)

echo
echo "applied (content already merged, new SHA): $applied"
echo "recorded in the ledger:                    $ledgered"
echo "UNREVIEWED:                                $unreviewed"

if [[ "$unreviewed" -gt 0 ]]; then
  echo
  echo "Needs a decision, then a row in $LEDGER:"
  printf '%s' "$unreviewed_list" | while IFS='|' read -r sha subject; do
    [[ -n "$sha" ]] && printf '  %-10s %s\n' "$sha" "$subject"
  done
  exit 1
fi

echo
echo "✓ nothing outstanding — every upstream commit is applied or deliberately recorded"
