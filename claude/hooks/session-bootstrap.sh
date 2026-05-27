#!/usr/bin/env bash
# session-bootstrap.sh — Full bootstrap on new session (matcher: startup)
# 1. Inject engram smart context
# 2. Check mesh health
# 3. Ensure auto-memory dir exists for this project
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "bootstrap"

IFS='|' read -r PROJECT PROJ_HASH REPO_ROOT <<< "$(project_info "$PWD")"
MEMORY_DIR="$HOME/.claude/projects/-${PROJ_HASH}/memory"

# 1. Engram context
CONTEXT=""
if http_ok "$ENGRAM_URL/health"; then
  CONTEXT=$(http_get "$ENGRAM_URL/context/smart?project=${PROJECT}&limit=15" | python3 -c "import sys,json; print(json.load(sys.stdin).get('context',''))" 2>/dev/null || true)
fi

# 2. Mesh health
HEALTH=""
if require_cmd meshctl; then
  HEALTH=$(meshctl health --json 2>/dev/null || true)
fi

# 3. Auto-memory check
MEMORY_OK=true
if [ ! -f "${MEMORY_DIR}/MEMORY.md" ]; then
  MEMORY_OK=false
fi

# Output
hook_section "Engram Memory"
if [ -n "$CONTEXT" ]; then
  echo "$CONTEXT" | head -40
else
  hook_warn "engram unreachable (context not injected)"
fi

echo ""
if [ -n "$HEALTH" ]; then
  hook_kv "mesh=$(echo "$HEALTH" | jq -r 'if .ok then "ok" else "degraded" end' 2>/dev/null)"
else
  hook_warn "meshctl unavailable"
fi

if [ "$MEMORY_OK" = true ]; then
  hook_kv "auto-memory=ok"
else
  hook_warn "auto-memory missing — create memory/MEMORY.md for this project"
fi

exit 0
