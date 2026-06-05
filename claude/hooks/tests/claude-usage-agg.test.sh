#!/usr/bin/env bash
# Tests for claude-usage-agg: reduce snapshots → tmux suffix (color stripped),
# rate-limit collapse, missing-data omission, lines sum, threshold/countdown,
# and pruning. NOCOLOR mode keeps assertions on text only.
set -uo pipefail
AGG="${BASH_SOURCE[0]%/*}/../../../home/dot_local/bin/executable_claude-usage-agg"
pass=0 fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); printf 'FAIL [%s] %s\n' "$1" "$2"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mk_snap() { # mk_snap <sid> <cost> <5h> <7d> <la> <lr>
  printf '{"session":"%s","cost_usd":%s,"five_hour_pct":%s,"seven_day_pct":%s,"lines_added":%s,"lines_removed":%s,"five_hour_resets_at":null,"seven_day_resets_at":null}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" >"$tmp/$1.json"
}
run() { CLAUDE_USAGE_NOCOLOR=1 CLAUDE_USAGE_NOPRUNE=1 bash "$AGG" "$tmp" "$@"; }

# 1. single session
mk_snap s1 4.12 48 12 320 110
[ "$(run s1)" = '$4.12  5h 48%  7d 12%  +320/-110' ] && ok || bad single "[$(run s1)]"

# 2. two sessions: cost+lines sum, rate-limits collapse to max
mk_snap s2 1.88 48 12 80 5
[ "$(run s1 s2)" = '$6.00  5h 48%  7d 12%  +400/-115' ] && ok || bad sum "[$(run s1 s2)]"

# 3. only live sids count (s2 present on disk but not live)
[ "$(run s1)" = '$4.12  5h 48%  7d 12%  +320/-110' ] && ok || bad liveonly "[$(run s1)]"

# 4. missing cost → cost segment omitted
mk_snap s3 null 50 20 10 2
[ "$(run s3)" = '5h 50%  7d 20%  +10/-2' ] && ok || bad nocost "[$(run s3)]"

# 5. missing rate-limits → those segments omitted (never 0%)
printf '{"session":"s4","cost_usd":2.5,"five_hour_pct":null,"seven_day_pct":null,"lines_added":null,"lines_removed":null,"five_hour_resets_at":null,"seven_day_resets_at":null}\n' >"$tmp/s4.json"
[ "$(run s4)" = '$2.50' ] && ok || bad norl "[$(run s4)]"

# 6. no live sessions → empty
[ -z "$(run)" ] && ok || bad empty "[$(run)]"

# 7. countdown appears only in yellow/red band (>=60) when a reset is in future
future=$(( $(date +%s) + 7800 ))   # ~2h10m
printf '{"session":"s5","cost_usd":1,"five_hour_pct":72,"seven_day_pct":12,"lines_added":0,"lines_removed":0,"five_hour_resets_at":%s,"seven_day_resets_at":null}\n' "$future" >"$tmp/s5.json"
o="$(run s5)"
case "$o" in *'5h 72% (2h'*) ok ;; *) bad countdown "[$o]" ;; esac
# low band shows no countdown even if reset present
printf '{"session":"s6","cost_usd":1,"five_hour_pct":20,"seven_day_pct":12,"lines_added":0,"lines_removed":0,"five_hour_resets_at":%s,"seven_day_resets_at":null}\n' "$future" >"$tmp/s6.json"
case "$(run s6)" in *'('*) bad nocountdown-low "[$(run s6)]" ;; *) ok ;; esac

# 8. pruning: a dead snapshot file is removed when prune enabled
mk_snap dead 9 9 9 9 9
CLAUDE_USAGE_NOCOLOR=1 bash "$AGG" "$tmp" s1 >/dev/null
[ -f "$tmp/dead.json" ] && bad prune "dead.json survived" || ok
[ -f "$tmp/s1.json" ]   && ok || bad prune-live "s1.json wrongly removed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
