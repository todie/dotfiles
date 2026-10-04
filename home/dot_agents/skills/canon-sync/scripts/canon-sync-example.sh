#!/usr/bin/env bash
# canon-sync-example.sh — preflight + read-only drift snapshot for a configured
# project root. Writes nothing. Usage:
#
#   ./canon-sync-example.sh [project-root]     # default: $PWD
set -euo pipefail

ROOT="${1:-$PWD}"
CFG="$ROOT/.canon-sync.yml"
[ -f "$CFG" ] || { echo "no .canon-sync.yml at $ROOT — refusing to guess" >&2; exit 1; }

: "${LINEAR_API_KEY:?LINEAR_API_KEY must be set in the environment}"

TICKETS_JSON="$(mktemp /tmp/canon-tickets.XXXXXX.json)"
PRS_JSON="$(mktemp /tmp/canon-prs.XXXXXX.json)"
trap 'rm -f "$TICKETS_JSON" "$PRS_JSON"' EXIT

# --- preflight: all three sources + budget, abort on first failure ----------
git -C "$ROOT" rev-parse --show-toplevel >/dev/null
gh auth status >/dev/null
linearctl --version
linearctl whoami >/dev/null
REMAINING="$(linearctl ratelimit --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["requests"]["remaining"])')"
[ "$REMAINING" -ge 300 ] || { echo "rate budget low: $REMAINING" >&2; exit 1; }

# --- config (yq-free minimal parse: flat keys we need) ----------------------
TEAM="$(sed -n 's/^  team: *//p' "$CFG" | head -1)"
PROJECT="$(sed -n 's/^  project: *//p' "$CFG" | head -1)"
REPO="$(sed -n 's/^repo: *//p' "$CFG" | head -1)"
[ -n "$TEAM" ] && [ -n "$PROJECT" ] && [ -n "$REPO" ] \
  || { echo "config needs linear.team, linear.project, repo" >&2; exit 1; }
echo "preflight ok: repo=$REPO linear=$TEAM/$PROJECT budget=$REMAINING"

# --- gather (read-only) ------------------------------------------------------
linearctl search --team "$TEAM" --project "$PROJECT" --state all --json > "$TICKETS_JSON"
gh pr list --repo "$REPO" --state all --limit 200 \
  --json number,title,state,mergedAt > "$PRS_JSON"

python3 - "$TICKETS_JSON" "$PRS_JSON" <<'PY'
import json, re, sys
tickets = {t["identifier"]: t for t in json.load(open(sys.argv[1]))}
prs = json.load(open(sys.argv[2]))
team = next(iter(tickets), "XXX").split("-")[0] if tickets else "XXX"
rx = re.compile(rf"{team}-\d+")
drift = []
for pr in prs:
    if pr["state"] != "MERGED":
        continue
    for tid in set(rx.findall(pr.get("title") or "")):
        t = tickets.get(tid)
        if t and t["stateType"] not in ("completed", "canceled"):
            drift.append((tid, t["state"], pr["number"]))
print("tickets=%d prs=%d pr_merged_ticket_open=%d" % (len(tickets), len(prs), len(drift)))
for tid, state, n in drift[:20]:
    print("  %s [%s] ← PR #%d merged — candidate close" % (tid, state, n))
PY
echo "read-only snapshot done; run the canon-sync skill for the full check set"
