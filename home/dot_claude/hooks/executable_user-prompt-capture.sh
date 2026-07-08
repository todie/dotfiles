#!/usr/bin/env bash
# user-prompt-capture.sh — POST every user prompt to reveried's /prompts
# endpoint so the engram user_prompts table actually sees traffic.
set -u
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "prompt-capture"
trap 'hook_trap_fail "$LINENO" "$BASH_COMMAND"' ERR

INPUT="$(safe_read_stdin)"

# Fires on EVERY prompt under a 2s harness timeout. Gate on a fast (1s) health
# check before the two sequential `-m 1` POSTs below — otherwise a
# reachable-but-wedged engram burns the full budget and the prompt is dropped
# mid-POST anyway. engram down/wedged → skip cleanly, prompt unaffected.
http_ok "$ENGRAM_URL/health" 1 || { echo '{}'; exit 0; }

SESSION_ID="$(json_field "$INPUT" '.session_id')"
USER_PROMPT="$(json_field "$INPUT" '.user_prompt // .prompt')"
PROJECT="$(json_field "$INPUT" '.project')"
CWD="$(json_field "$INPUT" '.cwd')"

# Derive project from cwd if not explicit (basename of the repo root).
if [ -z "${PROJECT}" ] && [ -n "${CWD}" ]; then
  PROJECT="$(basename "$CWD")"
fi

if [ -n "${SESSION_ID}" ] && [ -n "${USER_PROMPT}" ]; then
  # First, idempotent upsert of the session (FK target for prompts).
  SESSION_BODY="$(jq -n \
    --arg id "$SESSION_ID" \
    --arg project "${PROJECT:-default}" \
    --arg directory "${CWD:-/}" \
    '{id: $id, project: $project, directory: $directory}' 2>/dev/null)"

  [ -n "${SESSION_BODY}" ] && http_post "$ENGRAM_URL/sessions" "$SESSION_BODY" 1

  PROMPT_BODY="$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg content "$USER_PROMPT" \
    --arg project "${PROJECT:-default}" \
    '{session_id: $session_id, content: $content, project: $project}' 2>/dev/null)"

  [ -n "${PROMPT_BODY}" ] && http_post "$ENGRAM_URL/prompts" "$PROMPT_BODY" 1
fi

# Ambient Recall (CER-1369 slice 1 / CER-1420): surface cross-session memory
# relevant to THIS prompt as additionalContext. Server owns relevance floor +
# per-session dedupe (items empty on a silent turn). Hard 1s budget inside the
# 2s hook ceiling; endpoint absent (pre-0.10.x daemon) or down → clean no-op.
if [ -n "${SESSION_ID}" ] && [ -n "${USER_PROMPT}" ]; then
  AMBIENT_REQ="$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg project "${PROJECT:-default}" \
    --arg text "$USER_PROMPT" \
    '{session_id: $session_id, project: $project, text: $text}' 2>/dev/null)"
  AMBIENT_RESP="$(curl -sf -m 1 -X POST "$ENGRAM_URL/context/ambient" \
    -H 'Content-Type: application/json' -d "$AMBIENT_REQ" 2>/dev/null || true)"
  if [ -n "$AMBIENT_RESP" ]; then
    CONTEXT="$(echo "$AMBIENT_RESP" | jq -r '
      select((.items | length) > 0) |
      "## Ambient memory (relevant past context)\n" +
      ([.items[] | "- [\(.project)] **\(.title)**: \(.snippet)"] | join("\n"))
    ' 2>/dev/null)"
    if [ -n "$CONTEXT" ]; then
      jq -n --arg ctx "$CONTEXT" \
        '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
      exit 0
    fi
  fi
fi

echo '{}'
exit 0
