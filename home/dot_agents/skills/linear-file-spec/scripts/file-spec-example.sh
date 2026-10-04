#!/usr/bin/env bash
# file-spec-example.sh — runnable demo of the linear-file-spec write path.
#
# Default: dry-run — shows the two-part plan, writes nothing.
# With APPLY=1 and TEAM=<key>: files both parts through linearctl (bodies
# piped via heredoc into --desc -), wires B blocked-by A at creation, and
# re-reads each ticket via `linearctl show --json` (a different call than the
# one that wrote it).
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

TEAM="${TEAM:-}"
if [ "${APPLY:-0}" != "1" ]; then
  echo "[dry-run] would file 2 tickets (team: ${TEAM:-<required on apply>})"
  echo "  Part A: demo scaffold  (priority Low, blocked-by: —)"
  echo "  Part B: demo wiring    (priority Low, blocked-by: A)"
  echo "Re-run with APPLY=1 TEAM=<key> to write."
  exit 0
fi
[ -n "$TEAM" ] || { echo "TEAM is required with APPLY=1" >&2; exit 1; }

# --- pass 1: file A, then B wired to A -------------------------------------
A_JSON="$(cat <<'EOF' | linearctl file "demo: scaffold" --team "$TEAM" --label demo --priority 4 --desc - --json
Create the scaffold.

---

Part of the multi-part file-spec demo (parts A+B).
EOF
)"
A_ID="$(printf '%s' "$A_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["identifier"])')"
echo "filed $A_ID"

# Backward ref: B's blocker (A) already exists, so it wires at creation.
B_JSON="$(cat <<EOF | linearctl file "demo: wiring" --team "$TEAM" --label demo --priority 4 --blocked-by "$A_ID" --desc - --json
Wire the scaffold.

---

Part of the multi-part file-spec demo (parts A+B). Blocked by $A_ID.
EOF
)"
B_ID="$(printf '%s' "$B_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["identifier"])')"
echo "filed $B_ID (blocked by $A_ID)"

# --- re-read by a different call than wrote them ---------------------------
for id in "$A_ID" "$B_ID"; do
  linearctl show "$id" --json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%s\t%s\t%s\t%s" % (d["identifier"], d["state"], d["title"], d["url"]))'
done
