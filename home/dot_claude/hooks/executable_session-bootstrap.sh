#!/usr/bin/env bash
# session-bootstrap.sh — Full bootstrap on new session (matcher: startup)
# 1. Check mesh health
# 2. Ensure auto-memory dir exists for this project
#
# 3. Inject engram memory context (reveried /context/smart) for this project.
#    This was previously delegated to the external engram plugin's session-start
#    hook; that plugin was removed (we use our own reveried directly), so the
#    inject lives here again — single source, no duplicate dump.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "bootstrap"

IFS='|' read -r PROJECT PROJ_HASH REPO_ROOT <<< "$(project_info "$PWD")"
MEMORY_DIR="$HOME/.claude/projects/-${PROJ_HASH}/memory"

# 1. Mesh health
HEALTH=""
if require_cmd cortex; then
  HEALTH=$(cortex health --json 2>/dev/null || true)
fi

# 2. Auto-memory check
MEMORY_OK=true
if [ ! -f "${MEMORY_DIR}/MEMORY.md" ]; then
  MEMORY_OK=false
fi

# Output
if [ -n "$HEALTH" ]; then
  hook_kv "mesh=$(echo "$HEALTH" | jq -r 'if .ok then "ok" else "degraded" end' 2>/dev/null)"
else
  hook_warn "cortex unavailable"
fi

if [ "$MEMORY_OK" = true ]; then
  hook_kv "auto-memory=ok"
else
  hook_warn "auto-memory missing — create memory/MEMORY.md for this project"
fi

# 3. Engram context inject — reveried /context/smart for this project (graceful
#    skip if the daemon is down/wedged; never blocks session start).
if [ -n "${PROJECT:-}" ]; then
  CTX=$(curl -sf -m 3 "http://127.0.0.1:7437/context/smart?project=${PROJECT}&limit=15" 2>/dev/null || true)
  if [ -n "$CTX" ]; then
    printf '\n=== engram context (%s) ===\n%s\n' "$PROJECT" "$CTX" >&2
  fi
fi

# 4. Proactive-memory protocol nudge (previously injected by the external engram
#    plugin's session-start hook; restored here after that plugin's removal).
cat >&2 <<'PROTO'

=== engram memory protocol ===
mem_save proactively after: a decision, a bug fix (with root cause), a new
convention/workflow, a non-obvious gotcha, or a learned user preference.
Search memory before claiming no prior context exists. Session close → mem_session_summary.
PROTO

exit 0
