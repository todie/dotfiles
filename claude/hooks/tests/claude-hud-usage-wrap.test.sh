#!/usr/bin/env bash
# Tests for claude-hud-usage-wrap: snapshot extraction (--emit-snapshot) and
# render passthrough. jq-fed fixtures; asserts snapshot JSON + stdout.
set -uo pipefail
WRAP="${BASH_SOURCE[0]%/*}/../../../home/dot_local/bin/executable_claude-hud-usage-wrap"
pass=0 fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); printf 'FAIL [%s] %s\n' "$1" "$2"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
SNAP="$tmp/snap"; mkdir -p "$SNAP"

FULL='{"transcript_path":"/h/.claude/projects/p/05e66184-4aec-47f8-a41b-e66fd178275b.jsonl","cost":{"total_cost_usd":4.1234,"total_lines_added":320,"total_lines_removed":110},"rate_limits":{"five_hour":{"used_percentage":48,"resets_at":1749112800},"seven_day":{"used_percentage":12,"resets_at":1749600000}}}'

# 1. full snapshot has all fields
TMUX_PANE='%3' printf '%s' "$FULL" | TMUX_PANE='%3' bash "$WRAP" --emit-snapshot "$SNAP" --no-throttle
f="$SNAP/05e66184-4aec-47f8-a41b-e66fd178275b.json"
if [ -f "$f" ]; then ok; else bad full-written "no snapshot file"; fi
got="$(jq -r '[.session,.pane,(.cost_usd|tostring),(.five_hour_pct|tostring),(.lines_added|tostring)]|@tsv' "$f" 2>/dev/null)"
exp=$'05e66184-4aec-47f8-a41b-e66fd178275b\t%3\t4.1234\t48\t320'
[ "$got" = "$exp" ] && ok || bad full-fields "got=[$got]"

# 2. absent fields become null (not 0)
printf '%s' '{"transcript_path":"/x/abc.jsonl"}' | bash "$WRAP" --emit-snapshot "$SNAP" --no-throttle
g="$(jq -r '[.cost_usd,.five_hour_pct,.lines_added] | map(. // "null") | @tsv' "$SNAP/abc.json" 2>/dev/null)"
[ "$g" = $'null\tnull\tnull' ] && ok || bad absent-null "got=[$g]"

# 3. invalid JSON → no snapshot, no crash
before="$(ls "$SNAP" | wc -l)"
printf 'not json' | bash "$WRAP" --emit-snapshot "$SNAP" --no-throttle; rc=$?
after="$(ls "$SNAP" | wc -l)"
{ [ "$rc" -eq 0 ] && [ "$before" = "$after" ]; } && ok || bad bad-json "rc=$rc before=$before after=$after"

# 4. missing transcript_path → no snapshot (no key)
before="$(ls "$SNAP" | wc -l)"
printf '%s' '{"cost":{"total_cost_usd":1}}' | bash "$WRAP" --emit-snapshot "$SNAP" --no-throttle
after="$(ls "$SNAP" | wc -l)"
[ "$before" = "$after" ] && ok || bad no-session "wrote a snapshot without a session key"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
