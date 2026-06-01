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

# 1. coord dereg — idempotent (already-gone is fine)
if require_bin "$COORD"; then
  "$COORD" dereg >/dev/null 2>&1 || true
  log "coord dereg ok"
fi

# 2. engram session end — idempotent (HTTP 404 if already ended is fine)
if [ -n "$SESSION_ID" ]; then
  http_post "$ENGRAM_URL/sessions/${SESSION_ID}/end" '{}'
  log "engram end ok"
fi

# 3. drop any stale locks owned by this pid (defensive — coord dereg should handle)
if require_bin "$COORD"; then
  for lock in $("$COORD" status 2>/dev/null | jq -r '.locks[]?.resource // empty' 2>/dev/null); do
    "$COORD" unlock "$lock" >/dev/null 2>&1 || true
  done
fi

log "done"
hook_status "done sid=${SESSION_ID:-?} reason=${REASON}"
exit 0
