#!/usr/bin/env bash
# agent-offload-shim — PreToolUse hook on the Agent tool that tries
# local LLM first via maybe-offload. If local can produce a usable
# result, the hook DENIES the Agent call and surfaces the local result.

set -uo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "offload"
log_init /tmp/agent-offload-shim.log

MAYBE_OFFLOAD=/home/ctodie/.local/bin/maybe-offload

# Read the full hook payload from stdin
PAYLOAD=$(safe_read_stdin)
[ "$PAYLOAD" = '{}' ] && hook_allow

# Extract description + prompt from the Agent tool call
DESC=$(json_field "$PAYLOAD" '.tool_input.description')
PROMPT=$(json_field "$PAYLOAD" '.tool_input.prompt')
SUBAGENT=$(json_field "$PAYLOAD" '.tool_input.subagent_type')

# If we can't parse, fail open
[ -z "$PROMPT" ] && hook_allow

# Never shim specialized subagent types (only general-purpose)
case "$SUBAGENT" in
  ""|general-purpose) ;;
  *) hook_allow ;;
esac

# Run maybe-offload (90s budget)
OUT=$(timeout 90 "$MAYBE_OFFLOAD" "${DESC:-task}" "$PROMPT" 2>&1)
RC=$?

log "desc=${DESC:0:80} rc=$RC out=${OUT:0:200}"

case "$RC" in
  0)
    # OFFLOADED::<text>
    body=${OUT#OFFLOADED::}
    if [ -z "$body" ] || [ "$body" = "$OUT" ]; then
      hook_allow
    fi
    hook_deny "[agent-offload-shim] local LLM handled this — no Agent spawned. Result:

$body

(if you need a real subagent for this task, override by including \"SPAWN_AGENT_REQUIRED\" in the description and retry)"
    ;;
  1)
    # SPAWN::<reason> — let it through
    hook_allow
    ;;
  *)
    # error in the shim itself — fail open
    hook_allow
    ;;
esac
