#!/usr/bin/env bash
# worktree-jail.sh — thin shim to reverie-guard (CER-1097 cutover)
#
# When the reverie-guard binary is on PATH, this hook delegates jail-escape
# detection to `reverie-guard` (which runs the `check` logic in-process via
# the hook path). When the binary is absent, the legacy shell jail logic
# below runs.
#
# Dead regex blocks from the pre-cutover version (cd detection, git mutation
# redirect, force-push, filesystem write dst) are replaced by the binary.
# The legacy fallback carries only the path-extraction patterns the binary
# doesn't yet cover when running in shadow mode.
set -euo pipefail

INPUT=$(cat)

approve() { echo '{"decision":"approve"}'; exit 0; }
block()   { jq -n --arg r "$1" '{decision:"block", reason:$r}'; exit 0; }

[ "${REVERIE_JAIL_BYPASS:-0}" = "1" ] && approve

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(echo "$INPUT"  | jq -r '.cwd // .tool_input.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && approve

JAIL_ROOT=""
case "$CWD" in
    */.claude/worktrees/agent-*)
        JAIL_ROOT=$(echo "$CWD" | sed -E 's@(/\.claude/worktrees/agent-[A-Za-z0-9_-]+).*@\1@')
        JAIL_ROOT=$(readlink -m "$JAIL_ROOT" 2>/dev/null || echo "$JAIL_ROOT")
        ;;
esac
[ -z "$JAIL_ROOT" ] && approve

# --- Cutover: delegate to reverie-guard when available ----------------------
GUARD_BIN="${REVERIE_GUARD_BIN:-reverie-guard}"
if command -v "$GUARD_BIN" >/dev/null 2>&1; then
    # The binary's hook path already integrates jail-escape detection when
    # tool_input.cwd is present. We only reach here for the Edit/Write tools
    # where the binary's DangerousCommandPolicy doesn't check file_path scope.
    # For Bash tools, the binary already ran — this is a secondary check for
    # the worktree-specific path-scope (file writes outside the jail).
    :
fi

# --- Legacy fallback: file-path jail escape for Edit/Write -----------------
escapes_jail() {
    local p="$1"
    case "$p" in /*) ;; *) return 1 ;; esac
    local resolved
    resolved=$(readlink -m "$p" 2>/dev/null || echo "$p")
    case "$resolved" in
        "$JAIL_ROOT"|"$JAIL_ROOT"/*) return 1 ;;
        *) return 0 ;;
    esac
}

case "$TOOL" in
    Edit|Write|NotebookEdit)
        FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
        if [ -n "$FP" ] && escapes_jail "$FP"; then
            block "worktree-jail: subagent cannot Edit/Write outside its worktree.
  jail:   $JAIL_ROOT
  target: $FP"
        fi
        approve
        ;;
    *) approve ;;
esac
