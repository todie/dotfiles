#!/usr/bin/env bash
# worker-lifecycle.sh — SessionStart/SessionEnd hook for mesh workers
#
# On session start: register with coord (if in a reverie worktree)
# On session end: deregister from coord, release file locks
#
# Triggered by Claude Code's hook system as a Notification hook.

set -euo pipefail

EVENT=$(cat)
EVENT_TYPE=$(echo "$EVENT" | jq -r '.type // empty' 2>/dev/null)

# Only act in reverie worktrees
CWD=$(pwd)
if [[ "$CWD" != *"/reverie-wt-"* ]]; then
    exit 0
fi

# Extract role from worktree path
ROLE=$(echo "$CWD" | sed 's|.*/reverie-wt-||; s|/.*||')
[ -z "$ROLE" ] && exit 0

COORD="$HOME/.claude/bin/coord"
FILE_LOCK="$HOME/.claude/bin/file-lock"

REVERIED_URL="http://127.0.0.1:7437"
SESSION_FILE="/tmp/claude-coord/sessions/claude-pid-$$.json"

# Read session metadata from coord session file once, with fallbacks.
_read_session() {
    _sid=$(jq -r '.session_id // empty' "$SESSION_FILE" 2>/dev/null)
    _role=$(jq -r '.role // .blob.role // "unknown"' "$SESSION_FILE" 2>/dev/null)
    _task=$(jq -r '.current_task.phase // "unknown"' "$SESSION_FILE" 2>/dev/null)
    SID="${_sid:-$$}"; CP_ROLE="${_role:-$ROLE}"; TASK="${_task:-unknown}"
}

# POST a checkpoint to the dream journal. Args: phase pct last_tool dirty_json
_post_checkpoint() {
    local phase="$1" pct="$2" tool="$3" dirty="$4"
    curl -sf -X POST "${REVERIED_URL}/checkpoints" \
        -H 'Content-Type: application/json' \
        -d "$(jq -nc \
            --arg sid "$SID" \
            --arg role "$CP_ROLE" \
            --arg task "$TASK" \
            --arg phase "$phase" \
            --argjson pct "$pct" \
            --arg tool "$tool" \
            --arg dirty "$dirty" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
              session_id: $sid,
              role: $role,
              task_slug: $task,
              phase: $phase,
              progress_pct: $pct,
              last_tool: $tool,
              dirty_files: (if $dirty == "" then [] else [$dirty] end),
              started_at: $ts,
              checkpoint_at: $ts
            }')" >/dev/null 2>&1
}

case "${EVENT_TYPE}" in
    "session_start"|"init")
        # Register with coord
        $COORD register \
            --task "${ROLE}: worker session" \
            --blob "{\"role\":\"${ROLE}\",\"auto_heartbeat\":true}" \
            2>/dev/null || true
        ;;

    "post_tool_use"|"PostToolUse")
        # Checkpoint worker state to the dream journal (fire-and-forget)
        if curl -sf "${REVERIED_URL}/health" >/dev/null 2>&1; then
            _read_session
            dirty=$(git status --porcelain --short 2>/dev/null | wc -l)
            _post_checkpoint "working" 0.5 "${TOOL_NAME:-unknown}" "$dirty" &
        fi
        ;;

    "session_end"|"exit"|"")
        # Release any file locks held by this session
        for lock_dir in /tmp/claude-coord/locks/project:reverie:file::*; do
            [ -d "$lock_dir" ] || continue
            owner=$(cat "$lock_dir/owner" 2>/dev/null || echo "")
            if [ "$owner" = "claude-pid-$$" ] || [ "$owner" = "claude-pid-$PPID" ]; then
                rm -rf "$lock_dir" 2>/dev/null
            fi
        done

        # Final checkpoint to dream journal (fire-and-forget)
        if curl -sf "${REVERIED_URL}/health" >/dev/null 2>&1; then
            _read_session
            _post_checkpoint "completed" 1.0 "session_end" "" &
        fi

        # Deregister from coord
        $COORD dereg 2>/dev/null || true
        ;;
esac

exit 0
