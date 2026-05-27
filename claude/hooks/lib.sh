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
  # http_ok http://127.0.0.1:7437/health
  curl -sf "${1}" >/dev/null 2>&1
}

http_get() {
  curl -sf "$1" 2>/dev/null || echo ""
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
COORD="${HOME}/.claude/bin/coord"
REVERIED="${HOME}/.local/bin/reveried"
