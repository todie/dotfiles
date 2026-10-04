#!/usr/bin/env bash
# session-start-example.sh — the linear-session-ops session-start sequence:
# preconditions + one "what's already in progress" query. Read-only.
#
#   LINEAR_TEAM=CER LINEAR_PROJECT=Reverie ./session-start-example.sh
set -euo pipefail

: "${LINEAR_API_KEY:?LINEAR_API_KEY must be set in the environment}"
: "${LINEAR_TEAM:?set LINEAR_TEAM (e.g. CER) — no default}"
: "${LINEAR_PROJECT:?set LINEAR_PROJECT (exact name) — no default}"

# --- precondition trio -------------------------------------------------------
ver="$(linearctl --version)"
case "$ver" in
  0.[0-6].*) echo "linearctl >= 0.7.0 required (have $ver)" >&2; exit 1 ;;
esac
linearctl whoami
linearctl ratelimit --json \
  | python3 -c 'import json,sys; r=json.load(sys.stdin)["requests"]["remaining"]
assert r >= 300, f"rate budget low: {r}"
print(f"ratelimit remaining: {r}")'

# --- one glance at in-progress work, never a sweep ---------------------------
linearctl search --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" \
  --state started --assignee me --json \
  | python3 -c 'import json,sys
rows = json.load(sys.stdin)
print(f"in progress, assigned to me: {len(rows)}")
for t in rows[:10]:
    print("  %s\t%s\t%s" % (t["identifier"], t["state"], t["title"][:60]))'
