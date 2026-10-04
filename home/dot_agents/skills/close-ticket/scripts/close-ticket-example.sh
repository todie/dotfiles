#!/usr/bin/env bash
# close-ticket-example.sh — runnable close-ticket sequence: verify the SHA,
# comment the evidence, close, re-read.
#
#   ./close-ticket-example.sh <ISSUE-ID> <commit-sha> [--note "text"] [--repo <path>]
#   APPLY=1 ./close-ticket-example.sh <ISSUE-ID> <sha>   # writes (comment + close)
#
# Default is a dry-run: verifies the SHA, reads the ticket, prints the planned
# comment — writes nothing. APPLY=1 performs the comment + close on a ticket
# that is actually ready to close.
set -euo pipefail

: "${LINEAR_API_KEY:?LINEAR_API_KEY must be set in the environment}"

ID="${1:?usage: close-ticket-example.sh <ISSUE-ID> <sha> [--note t] [--repo p]}"
SHA="${2:?missing commit sha}"
shift 2
NOTE=""; REPO="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --note) NOTE="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$ID" =~ ^[A-Z]+-[0-9]+$ ]] || { echo "bad issue id: $ID" >&2; exit 2; }

# --- preflight trio ----------------------------------------------------------
linearctl --version
linearctl whoami >/dev/null
REMAINING="$(linearctl ratelimit --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["requests"]["remaining"])')"
[ "$REMAINING" -ge 300 ] || { echo "rate budget low: $REMAINING" >&2; exit 1; }

git -C "$REPO" rev-parse --verify "${SHA}^{commit}" >/dev/null \
  || { echo "SHA $SHA does not resolve in $REPO" >&2; exit 1; }
SHORT="$(git -C "$REPO" rev-parse --short=7 "$SHA")"

STATE_TYPE="$(linearctl show "$ID" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["stateType"])')"

if [ "${APPLY:-0}" != "1" ]; then
  echo "[dry-run] $ID stateType=$STATE_TYPE; would post:"
  echo "  Shipped in \`$SHORT\` on main.${NOTE:+ (plus note)}"
  [ "$STATE_TYPE" = "completed" ] \
    && echo "  already Done — comment only, no state flip" \
    || echo "  then close $ID and re-read via show --json"
  echo "Re-run with APPLY=1 to write."
  exit 0
fi

# Evidence comment FIRST, then the state flip.
{
  echo "Shipped in \`$SHORT\` on main."
  [ -n "$NOTE" ] && { echo; echo "$NOTE"; }
} | linearctl comment "$ID" --body - --json >/dev/null

if [ "$STATE_TYPE" = "completed" ]; then
  echo "$ID already Done — comment appended only"
else
  linearctl close "$ID" --json >/dev/null
fi

# Re-read by a different call than wrote it.
linearctl show "$ID" --json | python3 -c 'import json,sys
d = json.load(sys.stdin)
assert d["stateType"] == "completed", "close did not land: %s" % d["state"]
print("%s → %s ✓" % (d["identifier"], d["state"]))'
