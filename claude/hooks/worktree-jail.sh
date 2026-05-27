#!/usr/bin/env bash
# worktree-jail.sh — PreToolUse hook that JAILS subagents to their worktree.
#
# When a subagent is spawned via Agent(isolation: "worktree"), its cwd is
# `.../<repo>/.claude/worktrees/agent-<id>/`. Without enforcement the
# subagent can:
#   - Edit/Write absolute paths into the parent repo
#   - Bash `cd /path/to/main` then `git commit` against main's HEAD
#   - `git reset --hard` main (observed 2026-04-21)
#
# This hook reads the tool-call envelope from stdin and BLOCKS any
# Edit/Write/Bash whose effective target escapes the agent's jail.

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
        # Normalize lexically; do NOT require the dir to exist (escape attempts
        # against deleted worktrees still need to be blocked).
        JAIL_ROOT=$(readlink -m "$JAIL_ROOT" 2>/dev/null || echo "$JAIL_ROOT")
        ;;
esac
[ -z "$JAIL_ROOT" ] && approve

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

    Bash)
        CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        [ -z "$CMD" ] && approve

        cd_target=$(echo "$CMD" | grep -oE 'cd[[:space:]]+["'"'"']?(/[^[:space:]"'"'"';|&]+)' | head -1 | sed -E 's/^cd[[:space:]]+["'"'"']?//')
        if [ -n "$cd_target" ] && escapes_jail "$cd_target"; then
            block "worktree-jail: subagent cannot 'cd' outside its worktree.
  jail:   $JAIL_ROOT
  target: $cd_target"
        fi

        if echo "$CMD" | grep -qE '(^|[^a-zA-Z])git[[:space:]]+(commit|reset|rebase|checkout|push|merge|cherry-pick|am|stash[[:space:]]+(pop|apply|drop)|worktree[[:space:]]+(remove|prune|move))'; then
            if escapes_jail "$CWD"; then
                block "worktree-jail: subagent cannot run git mutation commands outside its worktree.
  jail: $JAIL_ROOT
  cwd:  $CWD"
            fi
            if echo "$CMD" | grep -qE 'git[[:space:]]+push.*(--force|--force-with-lease|-f([[:space:]]|$))'; then
                block "worktree-jail: subagents may not force-push."
            fi
        fi

        if echo "$CMD" | grep -qE '(>>?|tee[[:space:]]+(-a[[:space:]]+)?|sed[[:space:]]+-i)[[:space:]]+["'"'"']?/(home|tmp|etc|var|usr)/'; then
            for cand in $(echo "$CMD" | grep -oE '/(home|tmp|etc|var|usr)/[^[:space:]"'"'"';|&)]+'); do
                if escapes_jail "$cand"; then
                    block "worktree-jail: subagent cannot write outside jail.
  jail:   $JAIL_ROOT
  target: $cand"
                fi
            done
        fi

        approve
        ;;

    *) approve ;;
esac
