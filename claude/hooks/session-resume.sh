#!/usr/bin/env bash
# session-resume.sh — Light context inject on resume/compact/clear
# Skips health checks and auto-memory validation — just inject context.
# Also surfaces the latest context snapshot breadcrumb if one exists.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "resume"

IFS='|' read -r PROJECT _ _ <<< "$(project_info "$PWD")"

if ! http_ok "$ENGRAM_URL/health"; then
  hook_status "engram context skipped (unreachable)"
  exit 0
fi

# 1. Check for a recent context snapshot breadcrumb (from compact/clear)
# Search for recent snapshot via title match on observations endpoint
BREADCRUMB=$(python3 -c "
import urllib.request, json
from datetime import datetime
try:
  url = '${ENGRAM_URL}/search?q=context+snapshot+compact+clear&project=${PROJECT}&limit=1'
  data = json.loads(urllib.request.urlopen(url, timeout=2).read())
  if data:
    o = data[0]
    created = datetime.fromisoformat(o['created_at'])
    age = (datetime.utcnow() - created).total_seconds()
    if age < 3600:
      print(f\"Resumed from snapshot (obs #{o['id']}, {int(age/60)}m ago): {o['title']}\")
except: pass
" 2>/dev/null || true)

if [ -n "$BREADCRUMB" ]; then
  hook_status "$BREADCRUMB"
fi

# 2. Inject smart context
CONTEXT=$(http_get "$ENGRAM_URL/context/smart?project=${PROJECT}&limit=10" | python3 -c "import sys,json; print(json.load(sys.stdin).get('context',''))" 2>/dev/null || true)

if [ -n "$CONTEXT" ]; then
  hook_section "Engram Memory"
  echo "$CONTEXT" | head -25
fi

exit 0
