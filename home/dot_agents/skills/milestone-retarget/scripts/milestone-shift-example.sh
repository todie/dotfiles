#!/usr/bin/env bash
# milestone-shift-example.sh — runnable milestone-retarget --shift demo.
#
#   ./milestone-shift-example.sh --team CER --project linearctl --milestone "M3 · More workflows" --shift +1w
#   APPLY=1 ./milestone-shift-example.sh ...        # actually writes
#
# Default is a dry-run: resolves the milestone, computes the new date, prints
# the plan. APPLY=1 writes via `linearctl milestone update --apply` and then
# re-reads via `linearctl milestone --json` (a different call) to assert the
# date landed.
set -euo pipefail

: "${LINEAR_API_KEY:?LINEAR_API_KEY must be set in the environment}"

TEAM=""; PROJECT=""; MILESTONE=""; SHIFT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --milestone) MILESTONE="$2"; shift 2 ;;
    --shift) SHIFT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$TEAM" ] && [ -n "$PROJECT" ] && [ -n "$MILESTONE" ] && [ -n "$SHIFT" ] \
  || { echo "needs --team, --project, --milestone, --shift" >&2; exit 2; }
[[ "$SHIFT" =~ ^([+-])([0-9]+)([dw])$ ]] \
  || { echo "--shift must match ±Nd|±Nw" >&2; exit 2; }

# --- preflight -------------------------------------------------------------
linearctl --version
linearctl whoami >/dev/null
linearctl ratelimit --json >/dev/null

# --- resolve ---------------------------------------------------------------
PID="$(linearctl project list --team "$TEAM" --json \
  | python3 -c 'import json,sys
name = sys.argv[1]
hits = [p for p in json.load(sys.stdin) if p.get("name") == name]
assert len(hits) == 1, f"project {name!r}: {len(hits)} exact matches"
print(hits[0]["id"])' "$PROJECT")"
echo "project: $PROJECT ($PID)"

read -r MS_ID MS_DATE < <(linearctl milestone --project "$PID" --json \
  | python3 -c 'import json,sys
name = sys.argv[1]
hits = [m for m in json.load(sys.stdin)["milestones"] if m.get("name") == name]
assert len(hits) == 1, f"milestone {name!r}: {len(hits)} exact matches"
m = hits[0]
assert m.get("targetDate"), "milestone has no targetDate — use --set-date instead of --shift"
print(m["id"], m["targetDate"])' "$MILESTONE")
echo "milestone: $MILESTONE ($MS_ID) targetDate=$MS_DATE"

# --- compute new date ------------------------------------------------------
sign="${SHIFT:0:1}"; num="${SHIFT:1:${#SHIFT}-2}"; unit="${SHIFT: -1}"
[ "$unit" = "w" ] && num=$((num * 7))
[ "$sign" = "-" ] && num=$((-num))
NEW_DATE="$(date -d "$MS_DATE + $num days" +%F)"
echo "plan: $MS_DATE -> $NEW_DATE ($SHIFT)"

if [ "${APPLY:-0}" != "1" ]; then
  echo "[dry-run] re-run with APPLY=1 to write"
  exit 0
fi

# --- write, then re-read by a different call -------------------------------
linearctl milestone update "$MS_ID" --target-date "$NEW_DATE" --apply --json >/dev/null
ACTUAL="$(linearctl milestone --project "$PID" --json \
  | python3 -c 'import json,sys
ms = [m for m in json.load(sys.stdin)["milestones"] if m["id"] == sys.argv[1]]
print(ms[0]["targetDate"])' "$MS_ID")"
[ "$ACTUAL" = "$NEW_DATE" ] || { echo "VALIDATION FAILED: wanted $NEW_DATE, got $ACTUAL" >&2; exit 1; }
echo "validated: targetDate=$ACTUAL ✓"
