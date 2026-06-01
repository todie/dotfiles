#!/usr/bin/env bash
# session-bootstrap.sh — Full bootstrap on new session (matcher: startup)
# 1. Check mesh health
# 2. Ensure auto-memory dir exists for this project
#
# Engram memory context is intentionally NOT dumped here — the engram plugin's
# own session-start hook injects it (compact=1, server-trimmed). This hook used
# to also dump /context/smart, producing a duplicate ~40-line memory block per
# session; that was removed to cut per-session context.
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

exit 0
