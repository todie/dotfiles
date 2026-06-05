# tmux Claude Usage Indicator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold claude-hud usage data (cost, 5h/7d rate-limits, lines +/-) into the existing `@claude_glance` tmux indicator, consolidated across every live Claude pane.

**Architecture:** A statusLine wrapper tees Claude Code's stdin JSON to the unmodified claude-hud plugin while writing a throttled, atomic per-session usage snapshot. The `tmux-claude-glanced` daemon reduces those snapshots (sum cost, max rate-limits, sum lines) over its live-pane set via a standalone `claude-usage-agg` helper and appends a colored suffix to `@claude_glance`. Plugin untouched; zero shell added to the tmux render loop.

**Tech Stack:** bash, `jq`, tmux user-options, chezmoi (install), `bun` (runs claude-hud). Tests: `*.test.sh` (jq-fed fixtures, exit-code/output assertions).

**Spec:** `docs/2026-06-05-tmux-claude-usage-indicator-design.md` · **Ticket:** TOD-956 (Todie) · **Branch:** `feat/tmux-claude-usage-indicator`

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `home/dot_local/bin/executable_claude-hud-usage-wrap` | statusLine wrapper: render passthrough + snapshot emit | Create |
| `home/dot_local/bin/executable_claude-usage-agg` | reduce snapshots → colored tmux suffix + prune | Create |
| `home/dot_local/bin/executable_tmux-claude-glanced` | daemon: record `sid_of`, call agg, gate on `@claude_usage` | Modify |
| `home/dot_tmux.conf.d/claude.conf` | document `@claude_usage` toggle | Modify |
| `home/dot_claude/settings.json` | repoint `statusLine.command` to wrapper | Modify |
| `claude/hooks/tests/claude-hud-usage-wrap.test.sh` | extractor + passthrough tests | Create |
| `claude/hooks/tests/claude-usage-agg.test.sh` | reducer + formatting + prune tests | Create |

**Convention notes (read before starting):**
- chezmoi: `executable_` prefix → installed to `~/.local/bin/<name>` with +x. Files are plain (not `.tmpl`); edit the repo copy, then `chezmoi apply` to install. During dev, run the repo copy directly with `bash <path>`.
- Test pattern: see `claude/hooks/tests/guard-dangerous-commands.test.sh` — a `v()`-style helper feeds JSON via stdin and asserts. Run with `bash <test>`; contract is `pass`/`fail` counters + non-zero exit on any failure.
- Daemon discipline: NEVER add `#()`/shell to a tmux format string. All work stays in the daemon/agg.

---

## Task 1: Snapshot extractor (`claude-hud-usage-wrap --emit-snapshot`)

Build the snapshot-emit path first, in isolation and testable, before wiring render.

**Files:**
- Create: `home/dot_local/bin/executable_claude-hud-usage-wrap`
- Test: `claude/hooks/tests/claude-hud-usage-wrap.test.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/hooks/tests/claude-hud-usage-wrap.test.sh`:

```bash
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
g="$(jq -r '[.cost_usd,.five_hour_pct,.lines_added]|@tsv' "$SNAP/abc.json" 2>/dev/null)"
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/hooks/tests/claude-hud-usage-wrap.test.sh`
Expected: FAIL (wrapper does not exist yet → all assertions fail / file-not-found).

- [ ] **Step 3: Write minimal implementation (emit path only)**

Create `home/dot_local/bin/executable_claude-hud-usage-wrap`:

```bash
#!/usr/bin/env bash
# claude-hud-usage-wrap — Claude Code statusLine wrapper. Renders the per-pane
# claude-hud statusline UNCHANGED (tees stdin to the version-resolved plugin and
# forwards its stdout), and in the background writes a throttled, atomic
# per-session usage snapshot that tmux-claude-glanced consolidates across panes.
#
# cost.total_cost_usd + rate_limits.{five_hour,seven_day} + total_lines_* exist
# ONLY in this stdin JSON (never in the transcript), so this wrapper is the sole
# channel by which the tmux glance can learn them.
#
# Modes:
#   (default)            render claude-hud + bg snapshot
#   --emit-snapshot DIR  snapshot ONLY (no render) — used by tests
#   --no-throttle        always write (ignore the ~2s throttle) — used by tests
#
# Degrades silently: missing jq, invalid JSON, or absent fields never break the
# render. Snapshot fields absent from stdin are emitted as null (never 0).
set -uo pipefail

SNAP_DIR_DEFAULT="${XDG_RUNTIME_DIR:-/tmp}/claude-hud-usage"
THROTTLE=2

mode=render
snap_dir="$SNAP_DIR_DEFAULT"
throttle=1
while [ $# -gt 0 ]; do
  case "$1" in
    --emit-snapshot) mode=emit; snap_dir="${2:-$SNAP_DIR_DEFAULT}"; shift 2 ;;
    --no-throttle)   throttle=0; shift ;;
    *) shift ;;
  esac
done

# emit_snapshot <json> <dir> — derive session key, throttle, atomic write.
emit_snapshot() {
  local input="$1" dir="$2" session file age tmp now
  command -v jq >/dev/null 2>&1 || return 0
  session="$(printf '%s' "$input" \
    | jq -r '(.transcript_path // "") | split("/") | last | sub("\\.jsonl$";"")' 2>/dev/null)"
  [ -n "$session" ] && [ "$session" != "null" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  file="$dir/$session.json"
  now="$(date +%s)"
  if [ "$throttle" = 1 ] && [ -f "$file" ]; then
    age=$(( now - $(stat -c %Y "$file" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$THROTTLE" ] && return 0
  fi
  tmp="$file.tmp.$$"
  if printf '%s' "$input" | jq -c \
      --arg pane "${TMUX_PANE:-}" --argjson ts "$now" '
      {
        session: ((.transcript_path // "") | split("/") | last | sub("\\.jsonl$";"")),
        pane: $pane,
        ts: $ts,
        cost_usd:            (.cost.total_cost_usd            // null),
        five_hour_pct:       (.rate_limits.five_hour.used_percentage  // null),
        five_hour_resets_at: (.rate_limits.five_hour.resets_at        // null),
        seven_day_pct:       (.rate_limits.seven_day.used_percentage  // null),
        seven_day_resets_at: (.rate_limits.seven_day.resets_at        // null),
        lines_added:         (.cost.total_lines_added         // null),
        lines_removed:       (.cost.total_lines_removed       // null)
      }' >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

if [ "$mode" = emit ]; then
  emit_snapshot "$(cat)" "$snap_dir"
  exit 0
fi

# --- render mode added in Task 2 ---
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude/hooks/tests/claude-hud-usage-wrap.test.sh`
Expected: `4 passed, 0 failed` (the file is +x via chezmoi; tests invoke `bash "$WRAP"` so the bit is irrelevant in-repo).

- [ ] **Step 5: Commit**

```bash
git add home/dot_local/bin/executable_claude-hud-usage-wrap claude/hooks/tests/claude-hud-usage-wrap.test.sh
git commit -m "feat(tmux-usage): snapshot extractor for claude-hud-usage-wrap (TOD-956)"
```

---

## Task 2: Wrapper render passthrough

Add the latency-critical render path: resolve claude-hud, pipe stdin through, forward stdout, fire snapshot in the background.

**Files:**
- Modify: `home/dot_local/bin/executable_claude-hud-usage-wrap` (replace the `--- render mode ---` tail)
- Test: `claude/hooks/tests/claude-hud-usage-wrap.test.sh` (append a passthrough case)

- [ ] **Step 1: Write the failing test (append)**

Append before the final `printf`/exit in the test file:

```bash
# 5. render passthrough: stub claude-hud, assert stdout forwarded + snapshot side-written
stub="$tmp/fakehud"; mkdir -p "$stub/src"
cat >"$stub/src/index.ts" <<'EOS'
// stub: echo a fixed bar, ignore stdin
EOS
fakebun="$tmp/bun"; cat >"$fakebun" <<'EOB'
#!/usr/bin/env bash
cat >/dev/null   # drain stdin
printf 'BAR-OK'
EOB
chmod +x "$fakebun"
out="$(TMUX_PANE='%9' printf '%s' "$FULL" \
  | CLAUDE_HUD_BUN="$fakebun" CLAUDE_HUD_INDEX="$stub/src/index.ts" \
    XDG_RUNTIME_DIR="$tmp/run" bash "$WRAP")"
[ "$out" = "BAR-OK" ] && ok || bad passthrough "stdout=[$out]"
# snapshot also landed in the default dir under the overridden XDG_RUNTIME_DIR
sleep 0.3
[ -f "$tmp/run/claude-hud-usage/05e66184-4aec-47f8-a41b-e66fd178275b.json" ] && ok \
  || bad passthrough-snap "no bg snapshot written"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/hooks/tests/claude-hud-usage-wrap.test.sh`
Expected: the two new assertions FAIL (render mode is a bare `exit 0`).

- [ ] **Step 3: Implement render mode**

Replace the `# --- render mode added in Task 2 ---` / `exit 0` tail with:

```bash
# --- render mode ---
# Resolve the latest claude-hud plugin (same logic as the original statusLine
# command), overridable via env for tests.
resolve_index() {
  if [ -n "${CLAUDE_HUD_INDEX:-}" ]; then printf '%s' "$CLAUDE_HUD_INDEX"; return; fi
  local base d
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  d="$(ls -d "$base"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null \
        | awk -F/ '{ print $(NF-1) "\t" $0 }' \
        | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-)"
  printf '%s' "${d}src/index.ts"
}
resolve_bun() {
  if [ -n "${CLAUDE_HUD_BUN:-}" ]; then printf '%s' "$CLAUDE_HUD_BUN"; return; fi
  if [ -x "$HOME/.local/bin/bun" ]; then printf '%s' "$HOME/.local/bin/bun"
  else command -v bun 2>/dev/null || printf 'bun'; fi
}

input="$(cat)"
# Snapshot in the background so it never delays the rendered bar; fds detached.
( emit_snapshot "$input" "$snap_dir" ) >/dev/null 2>&1 &

bun="$(resolve_bun)"; index="$(resolve_index)"
printf '%s' "$input" | "$bun" --env-file /dev/null "$index"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude/hooks/tests/claude-hud-usage-wrap.test.sh`
Expected: `6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add home/dot_local/bin/executable_claude-hud-usage-wrap claude/hooks/tests/claude-hud-usage-wrap.test.sh
git commit -m "feat(tmux-usage): wrapper render passthrough + bg snapshot (TOD-956)"
```

---

## Task 3: Aggregate reducer (`claude-usage-agg`)

Standalone, daemon-callable, fully testable. Sum cost + lines over live sessions, collapse rate-limits to max, format a colored tmux-markup suffix, prune dead snapshots.

**Files:**
- Create: `home/dot_local/bin/executable_claude-usage-agg`
- Test: `claude/hooks/tests/claude-usage-agg.test.sh`

- [ ] **Step 1: Write the failing test**

Create `claude/hooks/tests/claude-usage-agg.test.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash claude/hooks/tests/claude-usage-agg.test.sh`
Expected: FAIL (agg does not exist).

- [ ] **Step 3: Write the implementation**

Create `home/dot_local/bin/executable_claude-usage-agg`:

```bash
#!/usr/bin/env bash
# claude-usage-agg — reduce per-session claude-hud usage snapshots into a tmux
# status suffix for tmux-claude-glanced. Reads <sid>.json files written by
# claude-hud-usage-wrap, SUMS cost + lines across the LIVE sessions, collapses
# the account-global rate-limits to their MAX, formats a colored tmux-markup
# segment, and prunes snapshots whose session is no longer live.
#
# Usage: claude-usage-agg <snap-dir> [live-sid ...]
#   Extra live sids may also be passed one-per-line on stdin.
# Output: tmux-markup string, segments joined by two spaces; empty if no data.
# Env: CLAUDE_USAGE_NOCOLOR=1 → plain text (tests); CLAUDE_USAGE_NOPRUNE=1 → keep
# all files (tests). Colors come from the @t_* tmux palette (defaults off-tmux).
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
dir="${1:-}"; [ -n "$dir" ] || exit 0; shift || true
[ -d "$dir" ] || exit 0

live=("$@")
if [ ! -t 0 ]; then
  while IFS= read -r s; do [ -n "$s" ] && live+=("$s"); done
fi

# palette + markup
pal() { local v; v="$(tmux show -gv "$1" 2>/dev/null)"; printf '%s' "${v:-$2}"; }
if [ -n "${CLAUDE_USAGE_NOCOLOR:-}" ]; then
  D=""; G=""; Y=""; R=""
  mk() { printf '%s' "$2"; }                       # mk <hex> <text> → text
else
  D="$(pal @t_dim white)"; G="$(pal @t_green green)"
  Y="$(pal @t_yellow yellow)"; R="$(pal @t_red red)"
  mk() { printf '#[fg=%s]%s#[default]' "$1" "$2"; }
fi
rl_color() { local p="${1%%.*}"; if   [ "${p:-0}" -ge 85 ] 2>/dev/null; then printf '%s' "$R"
             elif [ "${p:-0}" -ge 60 ] 2>/dev/null; then printf '%s' "$Y"
             else printf '%s' "$G"; fi; }
fmt_eta() { local r="${1:-}" now d h m; [ -n "$r" ] && [ "$r" != null ] || { printf ''; return; }
  now="$(date +%s)"; d=$(( r - now )); [ "$d" -gt 0 ] || { printf ''; return; }
  h=$(( d/3600 )); m=$(( (d%3600)/60 ))
  if [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"; else printf '%dm' "$m"; fi; }

# live sids → JSON array for jq selection
if [ "${#live[@]}" -gt 0 ]; then
  live_json="$(printf '%s\n' "${live[@]}" | jq -R . | jq -sc .)"
else
  live_json='[]'
fi

# Reduce across live snapshots in one jq slurp (handles floats + nulls).
read_ok=0
IFS=$'\t' read -r cost five seven five_r seven_r la lr < <(
  jq -rs --argjson live "$live_json" '
    (map(select(.session as $s | ($live|index($s)) != null))) as $L
    | [ ([$L[].cost_usd            | select(.!=null)] | add  // "")
      , ([$L[].five_hour_pct       | select(.!=null)] | max  // "")
      , ([$L[].seven_day_pct       | select(.!=null)] | max  // "")
      , ([$L[].five_hour_resets_at | select(.!=null)] | max  // "")
      , ([$L[].seven_day_resets_at | select(.!=null)] | max  // "")
      , ([$L[].lines_added         | select(.!=null)] | add  // "")
      , ([$L[].lines_removed       | select(.!=null)] | add  // "")
      ] | @tsv' "$dir"/*.json 2>/dev/null
) && read_ok=1

# Prune dead snapshots (unless disabled), only when we have a live set.
if [ -z "${CLAUDE_USAGE_NOPRUNE:-}" ] && [ "${#live[@]}" -gt 0 ]; then
  for f in "$dir"/*.json; do
    [ -e "$f" ] || continue
    sid="$(basename "$f" .json)"
    case " ${live[*]} " in *" $sid "*) ;; *) rm -f "$f" 2>/dev/null ;; esac
  done
fi

[ "$read_ok" = 1 ] || exit 0

segs=()
[ -n "$cost" ] && segs+=("$(mk "$D" "$(awk -v c="$cost" 'BEGIN{printf "$%.2f", c}')")")
if [ -n "$five" ]; then
  txt="5h ${five%%.*}%"
  [ "${five%%.*}" -ge 60 ] 2>/dev/null && { e="$(fmt_eta "$five_r")"; [ -n "$e" ] && txt="$txt ($e)"; }
  segs+=("$(mk "$(rl_color "$five")" "$txt")")
fi
if [ -n "$seven" ]; then
  txt="7d ${seven%%.*}%"
  [ "${seven%%.*}" -ge 60 ] 2>/dev/null && { e="$(fmt_eta "$seven_r")"; [ -n "$e" ] && txt="$txt ($e)"; }
  segs+=("$(mk "$(rl_color "$seven")" "$txt")")
fi
{ [ -n "$la" ] || [ -n "$lr" ]; } && segs+=("$(mk "$D" "+${la:-0}/-${lr:-0}")")

out=""
for s in "${segs[@]:-}"; do [ -n "$s" ] || continue; [ -n "$out" ] && out="$out  "; out="$out$s"; done
printf '%s' "$out"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash claude/hooks/tests/claude-usage-agg.test.sh`
Expected: `11 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add home/dot_local/bin/executable_claude-usage-agg claude/hooks/tests/claude-usage-agg.test.sh
git commit -m "feat(tmux-usage): claude-usage-agg snapshot reducer (TOD-956)"
```

---

## Task 4: Daemon integration (`tmux-claude-glanced`)

Record the pane→session id and append the usage suffix, gated on `@claude_usage`.

**Files:**
- Modify: `home/dot_local/bin/executable_tmux-claude-glanced`

> No new unit test (the daemon is an in-memory loop); Task 3 covers the reducer, and Task 6 covers end-to-end verification. Keep this patch surgical.

- [ ] **Step 1: Add `sid_of` to in-memory state**

In the `# ── in-memory state` block, add `sid_of` to the pane-keyed declarations:

```bash
declare -A tr_of win_of proj_of sid_of   # pane → transcript / window / project / session-id
```

And in the `rescan()` "forget panes that vanished" loop, add `sid_of[$pane]` to the `unset` list:

```bash
      unset 'tr_of[$pane]' 'win_of[$pane]' 'proj_of[$pane]' 'sid_of[$pane]' \
            'mt_of[$pane]' 'ctx_of[$pane]' 'act_of[$pane]' 'since_of[$pane]'
```

- [ ] **Step 2: Capture the session id during rescan**

In `rescan()`, the proc-scan loop already computes `$sid`. Record it alongside the transcript. Change the adopt block at the end of `rescan()`:

```bash
  for pane in "${!ntr[@]}"; do
    [ -n "${nwin[$pane]:-}" ] || continue
    tr_of[$pane]="${ntr[$pane]}"; win_of[$pane]="${nwin[$pane]}"
    proj_of[$pane]="${nproj[$pane]:-?}"
    : "${mt_of[$pane]:=0}"
  done
```

into one that also adopts `sid`. To do that, store sid in the scan: where `ntr[$pane]="$t"` is set, also set a parallel map. Add near the top of `rescan()`:

```bash
  local -A ntr=() nwin=() nproj=() nsid=() seen=()
```

set it in the proc loop right after `ntr[$pane]="$t"`:

```bash
    t="$(find "$projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1)"
    [ -n "$t" ] && [ -f "$t" ] && { ntr[$pane]="$t"; nsid[$pane]="$sid"; }
```

and adopt it in the final loop:

```bash
  for pane in "${!ntr[@]}"; do
    [ -n "${nwin[$pane]:-}" ] || continue
    tr_of[$pane]="${ntr[$pane]}"; win_of[$pane]="${nwin[$pane]}"
    proj_of[$pane]="${nproj[$pane]:-?}"; sid_of[$pane]="${nsid[$pane]:-}"
    : "${mt_of[$pane]:=0}"
  done
```

- [ ] **Step 3: Add the snapshot dir constant**

Near the other path constants at the top (`projects=`, `runtime=`):

```bash
snap_dir="${XDG_RUNTIME_DIR:-/tmp}/claude-hud-usage"   # written by claude-hud-usage-wrap
agg="$(command -v claude-usage-agg || printf '%s' "$HOME/.local/bin/claude-usage-agg")"
```

- [ ] **Step 4: Append the usage suffix in `tick()`**

In `tick()`, locate the global-aggregate block that builds `glance` (`◉/●/⤒`). Immediately AFTER the existing:

```bash
    [ "$max" -ge 0 ] && glance="${glance} #[fg=$(ctx_color "$max")]⤒${max}%#[default]"
  fi
```

insert, before the `if [ "$glance" != "$last_glance" ]` push:

```bash
  # Fold in claude-hud usage (cost / rate-limits / lines), gated by @claude_usage.
  if [ "$active" -gt 0 ] && [ "$(pal @claude_usage 1)" != 0 ] && [ -x "$agg" ]; then
    local live_sids=() p usage
    for p in "${!tr_of[@]}"; do [ -n "${sid_of[$p]:-}" ] && live_sids+=("${sid_of[$p]}"); done
    usage="$("$agg" "$snap_dir" "${live_sids[@]}" 2>/dev/null)"
    [ -n "$usage" ] && glance="${glance}  #[fg=${D}]·#[default]  ${usage}"
  fi
```

(`pal` and `D` are already defined in `tick()`; `ctx_color`/`rl_color` palettes match.)

- [ ] **Step 5: Syntax-check the daemon**

Run: `bash -n home/dot_local/bin/executable_tmux-claude-glanced`
Expected: no output (valid syntax).

- [ ] **Step 6: Commit**

```bash
git add home/dot_local/bin/executable_tmux-claude-glanced
git commit -m "feat(tmux-usage): fold usage suffix into @claude_glance via claude-usage-agg (TOD-956)"
```

---

## Task 5: Config toggle (`claude.conf`)

**Files:**
- Modify: `home/dot_tmux.conf.d/claude.conf`

- [ ] **Step 1: Document and default the toggle**

Immediately after the `set -g @claude_ctx_limit 1000000` block, add:

```bash
# Consolidated claude-hud usage in the status-right aggregate. When on (default),
# tmux-claude-glanced appends `· $<summed-cost> · 5h <max%> · 7d <max%> · +/-lines`
# to @claude_glance, sourced from per-session snapshots written by the statusLine
# wrapper (~/.local/bin/claude-hud-usage-wrap). Set to 0 to render only the
# session/context glance. (cost + rate-limits live ONLY in the statusLine stdin,
# never the transcript, so the wrapper is the sole channel for this data.)
set -g @claude_usage 1
```

- [ ] **Step 2: Verify tmux parses it (no live apply yet)**

Run: `tmux -f /dev/null start-server \; source-file home/dot_tmux.conf.d/claude.conf \; show -gv @claude_usage \; kill-server`
Expected: prints `1`.

- [ ] **Step 3: Commit**

```bash
git add home/dot_tmux.conf.d/claude.conf
git commit -m "feat(tmux-usage): @claude_usage toggle + docs (TOD-956)"
```

---

## Task 6: Wiring, install, end-to-end verification

Repoint the statusLine, install via chezmoi, restart the daemon, and verify live. This is the only task that touches the live machine and requires the `claude-config` coord lock.

**Files:**
- Modify: `home/dot_claude/settings.json` (chezmoi source) + live `~/.claude/settings.json`

- [ ] **Step 1: Confirm live statusLine matches the chezmoi source**

Run:
```bash
diff <(jq -S .statusLine ~/.claude/settings.json) \
     <(jq -S .statusLine home/dot_claude/settings.json) && echo IN-SYNC || echo DRIFT
```
Expected: `IN-SYNC`. If `DRIFT`, stop and reconcile by hand — do not blind-apply chezmoi over a drifted live file (it carries session-added permissions).

- [ ] **Step 2: Acquire the config lock**

Run: `~/.claude/bin/coord lock claude-config --reason "TOD-956 statusLine repoint"`
Expected: lock acquired (or surface the holder and wait).

- [ ] **Step 3: Repoint statusLine in the chezmoi source**

Edit `home/dot_claude/settings.json`, set:
```json
"statusLine": {
  "type": "command",
  "command": "/home/ctodie/.local/bin/claude-hud-usage-wrap"
}
```

- [ ] **Step 4: Install scripts + settings via chezmoi (targeted)**

Run:
```bash
chezmoi apply ~/.local/bin/claude-hud-usage-wrap ~/.local/bin/claude-usage-agg \
              ~/.local/bin/tmux-claude-glanced ~/.tmux.conf.d/claude.conf \
              ~/.claude/settings.json
```
Expected: files installed; verify executables:
```bash
ls -l ~/.local/bin/claude-hud-usage-wrap ~/.local/bin/claude-usage-agg
jq -c .statusLine ~/.claude/settings.json
```
Expected: both scripts are `-rwx`; statusLine command is the wrapper path.

- [ ] **Step 5: Release the config lock**

Run: `~/.claude/bin/coord unlock claude-config`

- [ ] **Step 6: Verify per-pane render is byte-identical**

Run (compares wrapper output vs the plugin directly on the same fixture):
```bash
FIX='{"transcript_path":"/t/x.jsonl","model":{"display_name":"Opus"},"context_window":{"current_usage":{"input_tokens":45000},"context_window_size":200000}}'
plugin="$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ | sort -V | tail -1)src/index.ts"
diff <(printf '%s' "$FIX" | ~/.local/bin/bun --env-file /dev/null "$plugin") \
     <(printf '%s' "$FIX" | ~/.local/bin/claude-hud-usage-wrap) && echo IDENTICAL
```
Expected: `IDENTICAL` (the wrapper only adds a side snapshot; stdout is unchanged).

- [ ] **Step 7: Restart the daemon and reload tmux config**

Run:
```bash
pkill -f tmux-claude-glanced 2>/dev/null; sleep 1
tmux source-file ~/.tmux.conf
~/.local/bin/tmux-claude-glanced --ensure
```
Expected: daemon respawns (singleton); `@claude_usage` is `1`.

- [ ] **Step 8: Verify the live aggregate**

With at least one Claude pane active for a few seconds (so a snapshot is written), run:
```bash
ls "${XDG_RUNTIME_DIR:-/tmp}/claude-hud-usage/"          # ≥1 <sid>.json
tmux show -gv @claude_glance                              # contains "$" cost + "5h"/"7d"
```
Expected: a snapshot file exists; `@claude_glance` shows the usage suffix, e.g. `●1 · $0.42 · 5h 6% · 7d 2% · +0/-0`. Toggle off to confirm gating:
```bash
tmux set -g @claude_usage 0; sleep 2; tmux show -gv @claude_glance   # no $ / 5h / 7d
tmux set -g @claude_usage 1
```

- [ ] **Step 9: Run the full test suite**

Run:
```bash
bash claude/hooks/tests/claude-hud-usage-wrap.test.sh
bash claude/hooks/tests/claude-usage-agg.test.sh
```
Expected: both report `0 failed`.

- [ ] **Step 10: Update the ticket + changelog, push, open PR**

```bash
# Update CHANGELOG.md if the repo keeps one (check first).
git add -A && git commit -m "chore(tmux-usage): wire statusLine + verification notes (TOD-956)"
git push -u origin feat/tmux-claude-usage-indicator
gh pr create --fill --title "tmux: consolidate claude-hud usage into @claude_glance (TOD-956)" \
  --body "Implements TOD-956. Spec: docs/2026-06-05-tmux-claude-usage-indicator-design.md"
```
Then mark TOD-956 acceptance checkboxes and move it to In Review.

---

## Self-Review

**Spec coverage:**
- Wrapper (tee + atomic + throttle + degrade) → Tasks 1–2. ✓
- Snapshot schema (session/pane/ts/cost/5h/7d/lines + null rules) → Task 1 jq body + test 2/4. ✓
- Daemon `sid_of` + sum/max/lines + live-gating + prune → Tasks 3–4. ✓
- Rate-limit color thresholds + reset countdown only in yellow/red → Task 3 `rl_color`/`fmt_eta` + tests 7. ✓
- `@claude_usage` toggle + no format-string change → Tasks 4–5. ✓
- settings.json repoint (chezmoi source + live, under lock, drift-check) → Task 6. ✓
- Byte-identical per-pane render → Task 6 step 6. ✓
- Tests for extractor + reducer (jq-fed fixtures) → Tasks 1/3. ✓
- No `#()` in tmux format strings → unchanged `claude.conf` status-right; verified by inspection. ✓

**Placeholder scan:** no TBD/TODO; every code step is complete and runnable.

**Type/name consistency:** snapshot field names identical across wrapper jq body, agg jq selectors, and tests (`cost_usd`, `five_hour_pct`, `five_hour_resets_at`, `seven_day_pct`, `seven_day_resets_at`, `lines_added`, `lines_removed`, `session`, `pane`). `claude-usage-agg` signature `<snap-dir> [live-sid ...]` matches the daemon call in Task 4 and tests in Task 3. `@claude_usage` spelled consistently in Tasks 4/5/6.
