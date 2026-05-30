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
# NB: pass ENGRAM_URL/PROJECT via the environment, never interpolated into the
# python source — a project dir named with an apostrophe would otherwise close
# the string literal and execute arbitrary code on resume. urlencode guards the
# query too. tz: coerce naive timestamps to UTC before the now()-created math.
BREADCRUMB=$(ENGRAM_URL="$ENGRAM_URL" PROJECT="$PROJECT" python3 -c '
import os, json, urllib.request, urllib.parse
from datetime import datetime, timezone
try:
    qs = urllib.parse.urlencode({"q": "context snapshot compact clear",
                                 "project": os.environ["PROJECT"], "limit": 1})
    url = os.environ["ENGRAM_URL"] + "/search?" + qs
    data = json.loads(urllib.request.urlopen(url, timeout=2).read())
    if data:
        o = data[0]
        created = datetime.fromisoformat(o["created_at"])
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc) - created).total_seconds()
        if age < 3600:
            oid, otitle = o["id"], o["title"]
            print(f"Resumed from snapshot (obs #{oid}, {int(age/60)}m ago): {otitle}")
except Exception:
    pass
' 2>/dev/null || true)

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
