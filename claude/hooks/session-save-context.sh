#!/usr/bin/env bash
# session-save-context.sh — PreCompact / SessionStart(clear) hook
# Saves a context snapshot to engram before the conversation is
# compacted or cleared, so knowledge survives the context loss.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "save-context"

http_ok "$ENGRAM_URL/health" || { hook_skip "engram unreachable"; exit 0; }
require_cmd jq || { hook_skip "jq missing"; exit 0; }

IFS='|' read -r PROJECT _ _ <<< "$(project_info "$PWD")"

# Build a session summary prompt — ask engram to snapshot current session.
# Read the real session_id from the event JSON on stdin (as session-cleanup.sh
# does). CLAUDE_SESSION_ID / CLAUDE_CONVERSATION_DIR are unset in this hook, so
# the old env-only fallback collapsed every snapshot onto the single
# topic_key=session/snapshot-unknown (5 cross-project rows already merged).
INPUT=$(safe_read_stdin)
SESSION_ID=$(json_field "$INPUT" '.session_id')
[ -z "$SESSION_ID" ] && SESSION_ID="${CLAUDE_SESSION_ID:-$(basename "${CLAUDE_CONVERSATION_DIR:-unknown}")}"

# Capture what we know: active tasks, recent tool calls, key decisions
# The hook runs *before* compaction, so the full context is still available.
# We save a lightweight breadcrumb so the post-compact/post-clear session
# can pick up where we left off.

BODY=$(jq -nc \
  --arg session_id "$SESSION_ID" \
  --arg project "$PROJECT" \
  --arg title "Context snapshot before compact/clear — $PROJECT $(date +%Y-%m-%dT%H:%M)" \
  --arg content "Session $SESSION_ID was compacted or cleared at $(date -Iseconds). Project: $PROJECT. CWD: $PWD. Check engram for recent observations and auto-memory for persistent state." \
  --arg topic_key "session/snapshot-${SESSION_ID}" \
  --arg type "manual" \
  '{
    session_id: $session_id,
    project: $project,
    title: $title,
    content: $content,
    topic_key: $topic_key,
    type: $type,
    scope: "project"
  }')

# POST observation directly to engram HTTP API
RESP=$(curl -sf -X POST "$ENGRAM_URL/observations" \
  -H 'Content-Type: application/json' \
  -d "$BODY" --max-time 3 2>/dev/null || echo "")

if [ -n "$RESP" ]; then
  OBS_ID=$(echo "$RESP" | jq -r '.id // empty' 2>/dev/null)
  hook_status "saved context snapshot obs=#${OBS_ID:-?}"
else
  hook_warn "failed to save context snapshot"
fi

exit 0
