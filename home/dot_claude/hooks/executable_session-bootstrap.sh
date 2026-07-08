#!/usr/bin/env bash
# session-bootstrap.sh — Full bootstrap on new session (matcher: startup)
# 1. Check core services health (reveried/redis/memcache via cortex)
# 2. Ensure auto-memory dir exists for this project
#
# 3. Inject engram memory context (reveried /context/smart) for this project.
#    This was previously delegated to the external engram plugin's session-start
#    hook; that plugin was removed (we use our own reveried directly), so the
#    inject lives here again — single source, no duplicate dump.
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "bootstrap"
trap 'hook_trap_fail "$LINENO" "$BASH_COMMAND"' ERR

IFS='|' read -r PROJECT PROJ_HASH REPO_ROOT <<< "$(project_info "$PWD")"
MEMORY_DIR="$HOME/.claude/projects/-${PROJ_HASH}/memory"

# 1. Services health
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
  hook_kv "services=$(echo "$HEALTH" | jq -r 'if .ok then "ok" else "degraded" end' 2>/dev/null)"
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

# 3b/3c. Last-session resume — ONLY when inside a git repository (operator:
#   "check for handoff and last session if we're in a repository directory").
#   Non-repo dirs (home, /tmp) stay quiet. Two surfaces:
#     3b. handoff  — bash CAN fetch it (curl reveried). Injected directly.
#     3c. Linear   — bash CANNOT reach the claude.ai Linear MCP. Emitted as a
#                    first-turn DIRECTIVE for Claude, not data fetched here.
if [ -n "${PROJECT:-}" ] && git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then

  # 3b. Latest RESUMABLE HANDOFF (written by /wrap) = the previous session's
  #     resumable state. Sorted by created_at, NOT FTS rank — rank returns stale
  #     handoffs first (verified: it surfaced a day-old handoff over the newest).
  #     Couples to the /wrap marker "RESUMABLE HANDOFF"; reword there → fix here.
  HANDOFF=$(curl -sf -m 4 "${ENGRAM_URL}/search?q=RESUMABLE%20HANDOFF&project=${PROJECT}&limit=8" 2>/dev/null \
    | jq -r '[.[] | select((.content // "") | test("RESUMABLE HANDOFF"))]
             | sort_by(.created_at) | last // empty
             | "TITLE: \(.title)\nWHEN:  \(.created_at)\n\n\(.content)"' 2>/dev/null || true)
  if [ -n "$HANDOFF" ]; then
    {
      printf '\n=== last session handoff (%s) ===\n' "$PROJECT"
      # Surface NEXT ACTION + TOP OPEN THREAD first, then the full body.
      printf '%s\n' "$HANDOFF" | grep -iE '^NEXT ACTION|^== TOP OPEN' | sed 's/^/» /' || true
      printf -- '---\n%s\n' "$HANDOFF"
    } >&2
  fi

  # 3c. Linear "what we've been up to" — DIRECTIVE, not data. A bash hook can't
  #     call the claude.ai Linear MCP, so Claude runs this on its first turn.
  #     "What we've been up to" = the operator's recent workspace activity
  #     (assignee=me), not this repo's tickets — works in any repo, no team map.
  #     Suppress for quick sessions with DOTFILES_SESSION_LINEAR=0.
  if [ "${DOTFILES_SESSION_LINEAR:-1}" != "0" ]; then
    cat <<'LINEAR'

<system-reminder>
SESSION-START DIRECTIVE (Linear): On your first turn, fetch a quick summary of
recent operator activity via the Linear MCP — list_issues assignee=me
updatedAt=-P3D orderBy=updatedAt. Summarize in 3-5 lines: what's In Progress,
what was recently completed, anything Urgent/blocked. Keep it terse; don't page.
Skip silently if the Linear MCP is unavailable.
</system-reminder>
LINEAR
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
