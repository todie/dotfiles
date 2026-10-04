#!/usr/bin/env bash
# close-ticket-example.sh — runnable close-ticket sequence: verify the SHA,
# comment the evidence, close, re-read.
#
#   ./close-ticket-example.sh <ISSUE-ID> <commit-sha> [--note "text"] [--repo <path>]
#
# Real writes: comments on and closes the given ticket. Use a ticket that is
# actually ready to close.
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

linearctl --version
linearctl whoami >/dev/null

git -C "$REPO" rev-parse --verify "${SHA}^{commit}" >/dev/null \
  || { echo "SHA $SHA does not resolve in $REPO" >&2; exit 1; }
SHORT="$(git -C "$REPO" rev-parse --short=7 "$SHA")"

# Already closed? Comment only.
STATE_TYPE="$(linearctl show "$ID" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["stateType"])')"
if [ "$STATE_TYPE" = "completed" ]; then
  echo "$ID already Done — commenting only"
fi

# Evidence comment FIRST, then the state flip.
{
  echo "Shipped in \`$SHORT\` on main."
  [ -n "$NOTE" ] && { echo; echo "$NOTE"; }
} | linearctl comment "$ID" --body - --json >/dev/null

if [ "$STATE_TYPE" != "completed" ]; then
  linearctl close "$ID" --json >/dev/null
fi

# Re-read by a different call than wrote it.
linearctl show "$ID" --json | python3 -c 'import json,sys
d = json.load(sys.stdin)
assert d["stateType"] == "completed", f"close did not land: {d[\"state\"]}"
print("%s → %s ✓" % (d["identifier"], d["state"]))'
