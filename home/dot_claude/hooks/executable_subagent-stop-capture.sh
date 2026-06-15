#!/usr/bin/env bash
# SubagentStop hook: auto-capture the last subagent turn through `reveried gate`.
#
# TOD-405. See docs/mvp-b/auto-capture-triggers.md (reverie repo) for the
# trigger contract. The harness pipes JSON like
#   { "session_id": "...", "transcript_path": "/path/to/transcript.jsonl", ... }
# to this hook's stdin on every subagent exit.
#
# IMPORTANT: everything this script writes to stdout/stderr is surfaced to the
# parent agent as a system-reminder. We MUST redirect ALL output to a log file
# or the {"decision":"accepted",...} JSON from `reveried gate` will pollute the
# parent's context window.

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "capture"
log_init "$HOME/.local/state/reveried/auto-capture.log"
# Alert fires before the log redirect below so it reaches Claude's context.
trap 'hook_trap_fail "$LINENO" "$BASH_COMMAND"' ERR

REJECT_LOG="$HOME/.local/state/reveried/gate-rejects.jsonl"
REVERIED_BIN="${REVERIED_BIN:-$HOME/.local/bin/engram}"
BUILD_CANDIDATE="$HOME/.claude/hooks/build-gate-candidate.py"

mkdir -p "$(dirname "$REJECT_LOG")"

# Redirect everything from here on. NO stdout from this point.
exec >>"${_HOOK_LOG}" 2>&1

# Read the harness hook payload from stdin once.
HOOK_JSON=$(cat)

SESSION_ID=$(json_field "$HOOK_JSON" '.session_id')
TRANSCRIPT_PATH=$(json_field "$HOOK_JSON" '.transcript_path')

if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ]; then
  log "SKIP: missing session_id or transcript_path"
  exit 0
fi
if [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "SKIP: transcript not found: $TRANSCRIPT_PATH"
  exit 0
fi
if ! require_bin "$REVERIED_BIN"; then
  log "SKIP: reveried binary not found: $REVERIED_BIN"
  exit 0
fi

# Build the candidate. Helper prints JSON on stdout, or empty string to skip.
CANDIDATE=$(python3 "$BUILD_CANDIDATE" --session "$SESSION_ID" --transcript "$TRANSCRIPT_PATH" 2>&1) || {
  log "build-gate-candidate failed: $CANDIDATE"
  exit 0
}
if [ -z "$CANDIDATE" ] || [ "$CANDIDATE" = "null" ]; then
  log "SKIP: candidate empty"
  exit 0
fi

# Feed the candidate to `reveried gate`. Exit 0 on accept, 1 on reject.
log "gate-submit: session=$SESSION_ID"
if printf '%s' "$CANDIDATE" | "$REVERIED_BIN" gate --reject-log "$REJECT_LOG"; then
  log "gate-accepted"
else
  RC=$?
  log "gate-rejected (rc=$RC) — details in $REJECT_LOG"
fi
# Hook itself always exits 0 — we don't want a rejected capture to error
# the subagent-stop pipeline.
exit 0
