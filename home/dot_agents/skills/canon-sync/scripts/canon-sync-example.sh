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

# --- preflight: all three sources, abort on first failure -------------------
git -C "$ROOT" rev-parse --show-toplevel >/dev/null
gh auth status >/dev/null
linearctl --version
linearctl whoami >/dev/null

# --- config (yq-free minimal parse: flat keys we need) ----------------------
TEAM="$(sed -n 's/^  team: *//p' "$CFG" | head -1)"
PROJECT="$(sed -n 's/^  project: *//p' "$CFG" | head -1)"
REPO="$(sed -n 's/^repo: *//p' "$CFG" | head -1)"
[ -n "$TEAM" ] && [ -n "$PROJECT" ] && [ -n "$REPO" ] \
  || { echo "config needs linear.team, linear.project, repo" >&2; exit 1; }
echo "preflight ok: repo=$REPO linear=$TEAM/$PROJECT"

# --- gather (read-only) ------------------------------------------------------
linearctl search --team "$TEAM" --project "$PROJECT" --state all --json > /tmp/canon-tickets.json
gh pr list --repo "$REPO" --state all --limit 200 \
  --json number,title,state,mergedAt > /tmp/canon-prs.json

python3 - <<'PY'
import json, re
tickets = {t["identifier"]: t for t in json.load(open("/tmp/canon-tickets.json"))}
prs = json.load(open("/tmp/canon-prs.json"))
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
print(f"tickets={len(tickets)} prs={len(prs)} pr_merged_ticket_open={len(drift)}")
for tid, state, n in drift[:20]:
    print(f"  {tid} [{state}] ← PR #{n} merged — candidate close")
PY
echo "read-only snapshot done; run the canon-sync skill for the full check set"
