#!/usr/bin/env bash
# file-bug-example.sh — runnable file-bug demo.
#
#   ./file-bug-example.sh                  # dry-run: renders the body, writes nothing
#   APPLY=1 TEAM=CER ./file-bug-example.sh # files a demo bug, then re-reads it
set -euo pipefail

: "${LINEAR_API_KEY:?LINEAR_API_KEY must be set in the environment}"

# --- preflight trio ----------------------------------------------------------
linearctl --version
linearctl whoami >/dev/null
REMAINING="$(linearctl ratelimit --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["requests"]["remaining"])')"
[ "$REMAINING" -ge 300 ] || { echo "rate budget low: $REMAINING" >&2; exit 1; }

TITLE="demo: file-bug example script smoke"

if [ "${APPLY:-0}" != "1" ]; then
  echo "[dry-run] would file: $TITLE"
  cat <<'EOF'
---
## Repro

- Run `file-bug-example.sh` with APPLY=1

## Evidence

```
n/a — scripted demo
```

## Root cause

Demo ticket filed by the file-bug example script; close on sight.

## Fix direction

- Close this ticket

## Acceptance

- [ ] Ticket exists with the five house sections
EOF
  echo "---"
  echo "Re-run with APPLY=1 TEAM=<key> to write."
  exit 0
fi

: "${TEAM:?TEAM is required with APPLY=1}"

# Heredoc piped into --desc - (never here-strings, never < redirect).
JSON="$(cat <<'EOF' | linearctl file "$TITLE" --team "$TEAM" --label bug --priority 4 --check-dups --desc - --json
## Repro

- Run `file-bug-example.sh` with APPLY=1

## Evidence

```
n/a — scripted demo
```

## Root cause

Demo ticket filed by the file-bug example script; close on sight.

## Fix direction

- Close this ticket

## Acceptance

- [ ] Ticket exists with the five house sections
EOF
)"
ID="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["identifier"])')"
URL="$(printf '%s' "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"

# Re-read by a different call than wrote it.
linearctl show "$ID" --json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)
assert "## Acceptance" in d["description"], "body did not land"
print("%s\t%s\tverified ✓" % (d["identifier"], d["state"]))'

echo "filed $ID — $URL"
