#!/bin/bash
# Idempotent SessionEnd cleanup.
# Safe to run multiple times: each step exits 0 if there's nothing to do.

set -u
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "cleanup"
log_init "$HOME/.claude/logs/session-cleanup.log"

INPUT=$(safe_read_stdin)
SESSION_ID=$(json_field "$INPUT" '.session_id')
REASON=$(json_field "$INPUT" '.reason')
[ -z "$REASON" ] && REASON="unknown"

log "start sid=${SESSION_ID:-?} reason=${REASON}"

# engram session end — idempotent (HTTP 404 if already ended is fine)
if [ -n "$SESSION_ID" ]; then
  http_post "$ENGRAM_URL/sessions/${SESSION_ID}/end" '{}'
  log "engram end ok"
fi

log "done"
hook_status "done sid=${SESSION_ID:-?} reason=${REASON}"
exit 0
