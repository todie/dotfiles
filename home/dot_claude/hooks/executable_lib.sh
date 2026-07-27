#!/usr/bin/env bash
# lib.sh — Shared utilities for Claude Code hooks
# Usage: source "${BASH_SOURCE[0]%/*}/lib.sh"
#
# Provides: JSON parsing, hook responses, HTTP ops, logging,
#           path resolution, command checks, project info.

# --- JSON input parsing ---

safe_read_stdin() { cat 2>/dev/null || echo '{}'; }

json_field() {
  # json_field "$input" '.tool_input.file_path'
  printf '%s' "$1" | jq -r "${2} // empty" 2>/dev/null || echo ""
}

# --- Hook response output (PreToolUse) ---

hook_allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

hook_deny() {
  local reason="$1"
  jq -n --arg r "$reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
}

hook_rewrite() {
  # hook_rewrite '{"command":"rtk git status"}'
  local updated="$1"
  jq -n --argjson u "$updated" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":$u}}'
  exit 0
}

# --- Command availability ---

require_cmd() {
  # require_cmd jq || exit 0
  command -v "$1" &>/dev/null
}

require_bin() {
  # require_bin ~/.local/bin/reveried || exit 0
  [ -x "$1" ]
}

check_version() {
  # check_version rtk 0.23.0
  local ver; ver=$("$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$ver" ] && return 1
  local maj min; maj=$(echo "$ver" | cut -d. -f1); min=$(echo "$ver" | cut -d. -f2)
  local req_maj req_min; req_maj=$(echo "$2" | cut -d. -f1); req_min=$(echo "$2" | cut -d. -f2)
  [ "$maj" -gt "$req_maj" ] && return 0
  [ "$maj" -eq "$req_maj" ] && [ "$min" -ge "$req_min" ]
}

# --- HTTP ops ---

http_ok() {
  # http_ok http://127.0.0.1:7437/health [timeout_secs]
  # --max-time bounds a reachable-but-wedged daemon (port open, no response —
  # e.g. during VACUUM / write-lock / dream-cycle pause) so it can't burn the
  # whole hook budget; connection-refused already returns instantly.
  curl -sf -m "${2:-2}" "${1}" >/dev/null 2>&1
}

http_get() {
  curl -sf -m "${2:-3}" "$1" 2>/dev/null || echo ""
}

http_post() {
  # http_post URL '{"key":"val"}' [timeout_secs]
  curl -s -o /dev/null -m "${3:-2}" \
    -X POST -H 'Content-Type: application/json' \
    -d "$2" "$1" 2>/dev/null || true
}

# --- Logging ---

_HOOK_LOG=""
log_init() {
  # log_init ~/.claude/logs/my-hook.log
  _HOOK_LOG="$1"
  mkdir -p "$(dirname "$_HOOK_LOG")"
}

log() {
  echo "[$(date -Iseconds)] $*" >> "${_HOOK_LOG:-/tmp/claude-hooks.log}" 2>/dev/null || true
}

# --- Project / path resolution ---

project_info() {
  # Returns: PROJECT|PROJ_HASH|REPO_ROOT
  local root; root=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || echo "${1:-.}")
  local name; name=$(basename "$root")
  # 2026-07-04 ~/projects reorg: dirs renamed into org buckets, but engram
  # project keys must stay canonical (history continuity). Map renamed
  # basenames back; manifest: ~/projects/_reorg-manifest-2026-07-04.tsv
  case "$root" in
    */projects/unsigned/paas)        name=unsigned-paas ;;
    */projects/unsigned/gg)          name=unsigned-gg ;;
    */projects/cerebral/site)        name=cerebral-work-site ;;
    */projects/cerebral/voicenotes)  name=cerebral-voicenotes ;;
    */projects/cerebral/models)      name=cerebral-models ;;
    */projects/templates/*)          name="template-$name" ;;
  esac
  local hash; hash=$(echo "$root" | sed 's|/|-|g; s|^-||')
  printf '%s|%s|%s' "$name" "$hash" "$root"
}

rel_path() {
  # Strip project root prefix to get crate-relative path
  # Works for any project: /home/user/projects/foo/crates/bar → crates/bar
  local p="$1"
  local root; root=$(git -C "$(dirname "$p")" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$root" ]; then
    p="${p#"$root"/}"
  else
    # Fallback: strip up to -wt-<role>/ or projects/<name>/
    p="${p#/home/*/projects/*/}"
    p="${p##*-wt-*/}"
  fi
  echo "$p"
}

worktree_role() {
  # worktree_role /home/user/projects/foo-wt-builder → builder
  # Generic: matches any <project>-wt-<role> pattern
  echo "$1" | sed 's|.*-wt-||; s|/.*||'
}

worktree_project() {
  # worktree_project /home/user/projects/foo-wt-builder → foo
  echo "$1" | sed 's|.*/\([^/]*\)-wt-.*|\1|'
}

in_worktree() {
  [[ "${1:-.}" == *"-wt-"* ]]
}

# --- Consistent output ---
#
# Hook stdout is injected into Claude's context. Keep it scannable:
#   hook: <name> | <status>
#   hook: <name> | key=val key=val
#
# _HOOK_NAME is set by the sourcing script or defaults to filename.

_HOOK_NAME=""
hook_name() { _HOOK_NAME="$1"; }

_hook_prefix() { echo "hook: ${_HOOK_NAME:-$(basename "${BASH_SOURCE[1]}" .sh)}"; }

# Print a status line: hook: bootstrap | ok
hook_status() {
  echo "$(_hook_prefix) | $*"
}

# Print a key=value line: hook: bootstrap | engram=up redis=up
hook_kv() {
  echo "$(_hook_prefix) | $*"
}

# Print a warning: hook: bootstrap | WARN: engram unreachable
hook_warn() {
  echo "$(_hook_prefix) | WARN: $*"
}

# Print an error: hook: bootstrap | ERROR: jq not found
hook_error() {
  echo "$(_hook_prefix) | ERROR: $*" >&2
}

# --- Reverie-repo detection ---
#
# True when the current working directory is inside the reverie monorepo.
# Used to gate loud stderr complaints: only emit when the operator can act.
is_reverie_repo() {
  local root; root=$(git -C "${PWD:-.}" rev-parse --show-toplevel 2>/dev/null || echo "")
  [[ "$root" == *"/projects/reverie" ]] || [[ "$root" == *"/projects/reverie-wt-"* ]]
}

# hook_alert: surface a failure into Claude's prompt context (stdout) so the
# model can see and act on it. Stdout is injected as a system-reminder for
# non-PreToolUse hooks (UserPromptSubmit, SessionStart, SubagentStop, Stop).
#
# Only fires inside the reverie repo — elsewhere the model can't fix hooks
# anyway, so we log silently instead.
#
# DO NOT use from PreToolUse hooks: their stdout is the JSON allow/deny
# channel. Use hook_error (stderr → UI only) there instead.
hook_alert() {
  local msg="$(_hook_prefix) | ALERT: $*"
  if is_reverie_repo; then
    echo "$msg"        # stdout → injected into model's prompt context
    echo "$msg" >&2   # stderr → also visible in the UI
  else
    log "ALERT: $*"
  fi
}

# hook_trap_fail: install as a trap ERR handler so unexpected script failures
# surface into Claude's context instead of disappearing. Usage at top of hook:
#   trap 'hook_trap_fail "$LINENO" "$BASH_COMMAND"' ERR
hook_trap_fail() {
  local line="${1:-?}" cmd="${2:-?}"
  hook_alert "unexpected failure at line $line: $cmd"
}

# Print a skip: hook: bootstrap | SKIP: no session_id
hook_skip() {
  echo "$(_hook_prefix) | SKIP: $*"
}

# Print a section header for multi-line output
hook_section() {
  echo ""
  echo "## $* (via ${_HOOK_NAME:-$(basename "${BASH_SOURCE[1]}" .sh)})"
}

# --- Circuit-breaker (Stop hook loop guard) ---
#
# Usage inside a Stop hook's terminal branch:
#   cb_check "hook-name" [max=3]
#
# Counts consecutive invocations keyed by PPID (the Claude process, stable
# per session). If the count reaches max, writes a diagnostic to engram and
# exits 0 to force a clean stop — preventing infinite Stop hook loops.
#
# cb_reset "hook-name"  — call at session start to clear the counter.

_CB_DIR="/tmp/claude-cb"

cb_check() {
  local hook="$1" max="${2:-3}"
  mkdir -p "$_CB_DIR"
  local key="$_CB_DIR/${PPID}-${hook}"
  local count=0
  [ -f "$key" ] && count=$(cat "$key" 2>/dev/null || echo 0)
  count=$((count + 1))
  echo "$count" > "$key"
  if [ "$count" -ge "$max" ]; then
    local msg="circuit-breaker tripped: hook=${hook} ppid=${PPID} count=${count} — possible Stop loop"
    # Write diagnostic to engram (best-effort)
    curl -sf -X POST "${ENGRAM_URL}/observations" \
      -H 'Content-Type: application/json' \
      -d "$(jq -nc \
          --arg h "$hook" --argjson c "$count" --arg p "$PPID" \
          '{type:"warning",content:("circuit-breaker tripped: hook="+$h+" ppid="+$p+" count="+($c|tostring)),project:"reverie",topic_key:("cb-"+$h)}')" \
      >/dev/null 2>&1 || true
    echo "hook: circuit-breaker | TRIPPED hook=${hook} count=${count} — forcing clean exit" >&2
    exit 0
  fi
}

cb_reset() {
  local hook="$1"
  rm -f "$_CB_DIR/${PPID}-${hook}" 2>/dev/null || true
}

# --- Constants ---

ENGRAM_URL="http://127.0.0.1:7437"
REVERIED="${HOME}/.local/bin/reveried"

# --- reverie capture auth (CER-1741) ---

# Mint (and cache) an Ed25519 JWT for reveried's authenticated routes.
#
#   reveried_jwt [project]
#
# Prints the token on stdout, or nothing at all. Every failure path returns
# empty rather than non-zero: these run on the hot prompt/tool path, where a
# missing token must degrade to unauthenticated capture, never to a blocked
# tool call. Callers source this under `set -u` with an ERR trap.
#
# Cache: per-project under /tmp at mode 0600, reused for 50min of the 1h TTL
# (the contract in reverie's ops/harness/README.md). The cache key is
# sanitized because the project name reaches a filesystem path.
reveried_jwt() {
  local project="${1:-${PROJECT:-default}}"
  local safe_project="${project//[^A-Za-z0-9_.-]/_}"
  local cache="/tmp/reveried-hook-jwt-${safe_project}.cache"

  # Serve from cache while >10min of the 1h TTL remains.
  if [ -s "$cache" ]; then
    local now mtime
    now="$(date +%s 2>/dev/null || echo 0)"
    # stat is BSD on darwin, GNU on linux — try both.
    mtime="$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0)"
    if [ "$now" -gt 0 ] && [ "$mtime" -gt 0 ] && [ $((now - mtime)) -lt 3000 ]; then
      cat "$cache" 2>/dev/null || true
      return 0
    fi
  fi

  # No binary or no signing key → unauthenticated, not an error.
  [ -x "$REVERIED" ] || return 0
  [ -n "${REVERIE_JWT_PRIVATE_KEY:-}" ] || return 0

  local tok
  tok="$("$REVERIED" token mint \
           --sub claude-code-capture \
           --scope 'mcp:write lcm:write' \
           --proj "$project" \
           --ttl-hours 1 2>/dev/null)" || return 0
  [ -n "$tok" ] || return 0

  # 0600 — the token is bearer credential material.
  (umask 077; printf '%s' "$tok" > "$cache") 2>/dev/null || true
  printf '%s' "$tok"
}

# Alias for the name used in reverie's ops/harness docs + hook headers.
reveried_jwt_for() { reveried_jwt "${1:-}"; }

# POST one turn to reveried's /v1/turns.
#
#   reverie_post_turn <project> <json_body>
#
# /v1/turns requires BOTH `mcp:write lcm:write` scopes and a --proj claim
# matching the event's project, so the token is minted per-project. If
# minting yields nothing the request still goes out unauthenticated: the
# daemon rejects it with a logged 401, which is a visible failure rather
# than a turn silently dropped on the client side.
reverie_post_turn() {
  local project="$1" body="$2"
  [ -n "$body" ] || return 0

  local tok; tok="$(reveried_jwt "$project")"

  # Build args as an array: a bare ${tok:+-H "..."} word-splits on the
  # space inside the header value and sends a malformed header.
  local -a auth=()
  [ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")

  curl -s -o /dev/null -m 2 -X POST \
    -H 'Content-Type: application/json' \
    "${auth[@]}" \
    -d "$body" \
    "$ENGRAM_URL/v1/turns" 2>/dev/null || true
}
