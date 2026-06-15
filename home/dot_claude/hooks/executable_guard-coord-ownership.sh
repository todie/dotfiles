#!/usr/bin/env bash
# guard-coord-ownership.sh — PreToolUse(Bash) hook. ENFORCED multi-pane ownership
# for the unsigned-paas merge-to-main path. Blocks `gh pr merge` / `git push … main`
# from any pane that does NOT own the "main-merge" resource per the ownership
# manifest. Pairs PREASSIGNED OWNERSHIP (the manifest) with ENFORCED LOCKING (this
# hook physically refuses the tool call) — the durable fix for the advisory-coord
# merge thrash (CER-1114: coord locks are advisory/bypassable; a hook is not).
#
# Manifest: /tmp/claude-coord/ownership.json
#   {"version":1,"resources":{"main-merge":{"owner":"claude-pid-N","ttl_until":<epoch>,"reason":"…"}}}
# Claim / release:  coord-own main-merge [--release] [--ttl MIN] [--reason "…"]
#
# SAFETY (blast-radius bounded):
#   • INERT unless a non-expired owner is declared (no manifest / no live owner → approve).
#   • FAILS OPEN on every ambiguity (no jq, no command, can't ID caller, not unsigned-paas).
#   • Scoped to the unsigned-paas repo only.
#   • Ownership entries carry a TTL so a crashed pane can't lock main forever.
#   • Bypass: `# allow-coord-override` in the command, or GUARD_COORD_OWNERSHIP_BYPASS=1.

set -uo pipefail
INPUT=$(cat 2>/dev/null) || exit 0
approve(){ echo '{"decision":"approve"}'; exit 0; }
block(){ jq -n --arg r "$1" '{decision:"block",reason:$r}' 2>/dev/null || printf '{"decision":"block","reason":"%s"}' "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || exit 0
[ "${GUARD_COORD_OWNERSHIP_BYPASS:-0}" = "1" ] && approve

MANIFEST="${COORD_OWNERSHIP_MANIFEST:-/tmp/claude-coord/ownership.json}"
[ -r "$MANIFEST" ] || approve                    # inert without a manifest

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL" = "Bash" ] || approve
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && approve
printf '%s' "$CMD" | grep -q '# *allow-coord-override' && approve

# --- is this a guarded merge-to-main operation? --------------------------------
guarded=0
printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' && guarded=1
printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+push([[:space:]]+[^|&;]*)?[[:space:]]main([[:space:]]|$|:)' && guarded=1
printf '%s' "$CMD" | grep -qE 'HEAD:(refs/heads/)?main([[:space:]]|$)' && guarded=1
[ "$guarded" = 1 ] || approve

# --- scope to the unsigned-paas repo -------------------------------------------
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
cd_t=$(printf '%s' "$CMD" | grep -oE 'cd[[:space:]]+["'"'"']?(/[^[:space:]"'"'"';|&]+)' | head -1 | sed -E 's/^cd[[:space:]]+["'"'"']?//' || true)
[ -n "$cd_t" ] && CWD="$cd_t"
common=$(git -C "${CWD:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
in_repo=0
case "$common" in *unsigned-paas/.git*|*unsigned-paas-*/.git*) in_repo=1 ;; esac
# gh pr merge can run from anywhere with -R; treat an explicit repo ref as in-scope
printf '%s' "$CMD" | grep -qE 'unsigned-gg/unsigned-paas|[^a-z]unsigned-paas([^-a-z]|$)' && in_repo=1
[ "$in_repo" = 1 ] || approve

# --- live owner of main-merge (TTL-honored) ------------------------------------
now=$(date +%s)
owner=$(jq -r --argjson now "$now" '.resources["main-merge"] // empty | select((.ttl_until // 9999999999) > $now) | .owner // empty' "$MANIFEST" 2>/dev/null)
[ -z "$owner" ] && approve                       # no live owner → inert

# --- identify the calling pane via /proc ancestry → claude-pid-<pid> -----------
caller=""; pid=$PPID
for _ in $(seq 1 14); do
  [ -r "/proc/$pid/comm" ] || break
  c=$(cat "/proc/$pid/comm" 2>/dev/null || echo)
  case "$c" in claude|claude-code) caller="claude-pid-$pid"; break ;; esac
  np=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo)
  { [ -n "$np" ] && [ "$np" != "0" ] && [ "$np" != "$pid" ]; } || break
  pid=$np
done
[ -z "$caller" ] && approve                      # can't ID caller → fail open
[ "$caller" = "$owner" ] && approve              # owner → allowed

reason=$(jq -r '.resources["main-merge"].reason // "(none)"' "$MANIFEST" 2>/dev/null)
block "guard-coord-ownership: BLOCKED merge-to-main — this pane ($caller) does NOT own 'main-merge'.
  owner: $owner    reason: $reason

Preassigned ownership + enforced lock (anti-thrash; advisory coord locks were bypassable, CER-1114).
Choose one:
  • hand off to the owner:    coord send $owner ready '<pr#> ready to merge'
  • claim it (if it's yours): coord-own main-merge --reason '<why>'
  • one-off intentional bypass: append  # allow-coord-override"
