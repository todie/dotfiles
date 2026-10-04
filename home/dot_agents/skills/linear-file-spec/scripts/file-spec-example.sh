#!/usr/bin/env bash
# file-spec-example.sh — runnable demo of the linear-file-spec write path.
#
# Default: dry-run — parses a tiny two-part spec and prints the plan, writes
# nothing. With APPLY=1 and TEAM=<key>: files both parts through linearctl,
# wires B blocked-by A, and re-reads each ticket via `linearctl show --json`
# (a different call than the one that wrote it).
#
#   ./file-spec-example.sh                 # dry-run, safe
#   APPLY=1 TEAM=CER ./file-spec-example.sh
set -euo pipefail

: "${LINEAR_API_KEY:?LINEAR_API_KEY must be set in the environment}"

# --- preflight -------------------------------------------------------------
ver="$(linearctl --version)"
case "$ver" in
  0.[0-6].*) echo "linearctl >= 0.7.0 required (have $ver)" >&2; exit 1 ;;
esac
linearctl whoami >/dev/null   # auth failure aborts here; never retried
remaining="$(linearctl ratelimit --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["requests"]["remaining"])')"
[ "$remaining" -ge 300 ] || { echo "rate budget low: $remaining" >&2; exit 1; }

# --- the tiny spec ---------------------------------------------------------
SPEC="$(mktemp /tmp/file-spec-demo.XXXXXX.md)"
trap 'rm -f "$SPEC"' EXIT
cat > "$SPEC" <<'EOF'
---
team: PLACEHOLDER
labels: demo
---

# Demo spec

Two parts; B depends on A.

## Part A: demo scaffold
**priority**: Low
**blocked-by**: (none)

Create the scaffold.

## Part B: demo wiring
**priority**: Low
**blocked-by**: A

Wire the scaffold.
EOF

TEAM="${TEAM:-}"
if [ "${APPLY:-0}" != "1" ]; then
  echo "[dry-run] would file 2 tickets (team: ${TEAM:-<required on apply>})"
  grep '^## Part' "$SPEC" | sed 's/^/  /'
  echo "Re-run with APPLY=1 TEAM=<key> to write."
  exit 0
fi
[ -n "$TEAM" ] || { echo "TEAM is required with APPLY=1" >&2; exit 1; }

# --- pass 1: file A, then B wired to A -------------------------------------
file_part() { # title, extra args..., body on stdin
  local title="$1"; shift
  linearctl file "$title" --team "$TEAM" --label demo --priority 4 \
    --desc - --json "$@"
}

body_a="$(sed -n '/## Part A/,$p' "$SPEC" | sed -n '4,/^$/p')"
A_JSON="$(file_part "demo: scaffold" <<< "$body_a
---
Part of multi-part spec demo. Full proposal: $SPEC")"
A_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["identifier"])' <<< "$A_JSON")"
echo "filed $A_ID"

body_b="$(sed -n '/## Part B/,$p' "$SPEC" | sed -n '4,/^$/p')"
B_JSON="$(file_part "demo: wiring" --blocked-by "$A_ID" <<< "$body_b
---
Part of multi-part spec demo. Full proposal: $SPEC")"
B_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["identifier"])' <<< "$B_JSON")"
echo "filed $B_ID (blocked by $A_ID)"

# --- re-read by a different call than wrote them ---------------------------
for id in "$A_ID" "$B_ID"; do
  linearctl show "$id" --json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%s\t%s\t%s\t%s" % (d["identifier"], d["state"], d["title"], d["url"]))'
done
