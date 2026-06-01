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

        # `|| true`: a no-match grep exits 1, which under `set -e` previously
        # aborted the hook with empty stdout BEFORE any check ran — failing the
        # jail open for every command without a literal `cd /abspath`.
        cd_target=$(echo "$CMD" | grep -oE 'cd[[:space:]]+["'"'"']?(/[^[:space:]"'"'"';|&]+)' | head -1 | sed -E 's/^cd[[:space:]]+["'"'"']?//' || true)
        if [ -n "$cd_target" ] && escapes_jail "$cd_target"; then
            block "worktree-jail: subagent cannot 'cd' outside its worktree.
  jail:   $JAIL_ROOT
  target: $cd_target"
        fi

        # git mutations. Detect LOOSELY (git + a mutating subcommand anywhere,
        # so `git -C dir reset` and `git --git-dir=x commit` are caught) but
        # block PRECISELY — only when the cwd escapes the jail OR the command
        # redirects git at another tree via -C/--git-dir/--work-tree. A mutation
        # confined to the jail (cwd=jail, no redirect) stays allowed.
        if echo "$CMD" | grep -qE '(^|[^a-zA-Z])git([[:space:]]|$)' \
           && echo "$CMD" | grep -qE '(^|[^-[:alnum:]])(commit|reset|rebase|checkout|merge|cherry-pick|am|stash|worktree[[:space:]]+(remove|prune|move))([^-[:alnum:]]|$)'; then
            git_redirect=$(echo "$CMD" | grep -oE '(-C|--git-dir[=[:space:]]|--work-tree[=[:space:]])[[:space:]]*["'"'"']?/[^[:space:]"'"'"';|&]+' | grep -oE '/[^[:space:]"'"'"';|&]+' | head -1 || true)
            if escapes_jail "$CWD" || { [ -n "$git_redirect" ] && escapes_jail "$git_redirect"; }; then
                block "worktree-jail: subagent cannot run git mutation commands outside its worktree.
  jail:     $JAIL_ROOT
  cwd:      $CWD
  redirect: ${git_redirect:-none}"
            fi
        fi
        # Force-push is never allowed from a subagent, target irrespective.
        if echo "$CMD" | grep -qE '(^|[^a-zA-Z])git([[:space:]]|$)' \
           && echo "$CMD" | grep -qE '(^|[^-[:alnum:]])push([^-[:alnum:]]|$)' \
           && echo "$CMD" | grep -qE '(--force([^-[:alnum:]]|=|$)|--force-with-lease|(^|[[:space:]])-[a-zA-Z]*f([[:space:]]|$)|[[:space:]]\+[^[:space:]:]+(:|[[:space:]]|$))'; then
            block "worktree-jail: subagents may not force-push."
        fi

        # Filesystem writes into another tree. Redirect / tee / sed -i name the
        # destination directly; cp/mv/install/rsync put it LAST (so reading or
        # copying INTO the jail — last path stays inside — is not blocked).
        write_dst=""
        case "$CMD" in
            *">"*|*tee*)
                # redirect / tee name the destination right after the operator
                write_dst=$(echo "$CMD" | grep -oE '(>>?|tee[[:space:]]+(-a[[:space:]]+)?)[[:space:]]*["'"'"']?/[^[:space:]"'"'"';|&]+' | grep -oE '/[^[:space:]"'"'"';|&]+' | head -1 || true)
                ;;
            *"cp "*|*"mv "*|*"install "*|*"rsync "*|*"sed -i"*|*"sed --in-place"*)
                # destination = last token of the first command segment (cut at
                # ; | &). A relative dest resolves inside the jail (escapes_jail
                # returns false), so copies/edits INTO the jail are not blocked.
                # (sed -i's target file is its LAST arg, after the script.)
                first_seg=$(printf '%s' "$CMD" | sed -E 's/[[:space:]]*[;|&].*$//')
                write_dst=$(printf '%s' "$first_seg" | awk '{print $NF}' | sed -E "s/^[\"']//; s/[\"']\$//")
                ;;
            *"dd "*)
                write_dst=$(echo "$CMD" | grep -oE 'of=["'"'"']?/[^[:space:]"'"'"';|&]+' | sed -E 's/^of=["'"'"']?//' | head -1 || true)
                ;;
        esac
        if [ -n "$write_dst" ] && escapes_jail "$write_dst"; then
            block "worktree-jail: subagent cannot write outside jail.
  jail:   $JAIL_ROOT
  target: $write_dst"
        fi

        approve
        ;;

    *) approve ;;
esac
