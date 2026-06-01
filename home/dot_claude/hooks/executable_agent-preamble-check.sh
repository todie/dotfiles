#!/usr/bin/env bash
# agent-preamble-check.sh — PreToolUse validator for `Agent` tool calls
# (TOD-769).
#
# Blocks Agent dispatch if the prompt is missing the canonical preamble
# keywords documented in docs/coord/agent-dispatch.md (Part 2):
#
#   1. worktree       — CWD discipline
#   2. merge policy   — "Do NOT merge" or an explicit merge keyword
#   3. report format  — "report" or "Report"
#
# A missing `heartbeat` keyword is a soft warn (not a block) because the
# heartbeat convention landed after many legacy prompt templates.
#
# Input:  JSON blob on stdin (Claude Code tool-call envelope).
# Output: JSON verdict — {"decision":"approve"} or
#         {"decision":"block","reason":"..."} or
#         {"decision":"approve","systemMessage":"..."}
# Exit:   0 always — decision is in the JSON.
#
# Bypasses:
#   * `# preamble: skip` on the first ~200 chars of the prompt
#   * short prompts (<500 chars) — not worth the overhead
#   * non-Agent tool calls — passthrough

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

approve() { echo '{"decision":"approve"}'; exit 0; }
block()   { local reason="$1"; jq -n --arg r "$reason" '{decision:"block", reason:$r}'; exit 0; }
warn()    { local msg="$1"; jq -n --arg m "$msg" '{decision:"approve", systemMessage:$m}'; exit 0; }

# Non-Agent tool calls — passthrough.
if [ "$TOOL_NAME" != "Agent" ]; then
    approve
fi

PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
SUBAGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)

# Bypass 1: explicit skip directive on the first ~300 chars (preamble OR preflight).
if echo "$PROMPT" | head -c 300 | grep -qE "^#[[:space:]]*(preamble|preflight|research):[[:space:]]*(skip|true)"; then
    approve
fi

# Bypass 2: short prompts aren't real agent dispatches.
if [ "${#PROMPT}" -le 500 ]; then
    approve
fi

# Bypass 3: known research-only subagent types — they don't touch code.
case "$SUBAGENT" in
    Explore|Plan|claude-code-guide) approve ;;
    rust-skills:*|claude-md-management:*|claude-code-setup:*) approve ;;
esac

missing=()

echo "$PROMPT" | grep -qiE "worktree" \
    || missing+=("worktree-cwd")

# Merge policy: accept either an explicit "Do NOT merge" directive or any
# sentence containing the word "merge" (so "merge: ..." instructions also
# pass). Block if the prompt says nothing at all about merge behaviour.
echo "$PROMPT" | grep -qE "[Dd]o NOT merge|[Dd]o not merge|merge" \
    || missing+=("merge-policy")

echo "$PROMPT" | grep -qE "[Rr]eport" \
    || missing+=("report-format")

if [ "${#missing[@]}" -gt 0 ]; then
    block "agent-preamble-check: Agent prompt is missing required preamble keywords: ${missing[*]}.

Remediation: prepend the canonical preamble from docs/coord/agent-dispatch.md
(Part 2, 'Copy-pasteable composite preamble'). Required keywords:
  - worktree        (CWD discipline block)
  - Do NOT merge / merge policy (deliverables block)
  - report / Report (report-format block)

Bypass (non-code research agents only): add '# preamble: skip' as the first
line of the prompt."
fi

# Soft check — heartbeat keyword. Warn, don't block.
if ! echo "$PROMPT" | grep -qiE "heartbeat"; then
    warn "agent-preamble-check: Agent prompt is missing the 'heartbeat' keyword. The orchestrator will be blind to mid-run progress. See docs/coord/agent-dispatch.md (Part 2, Heartbeat block)."
fi

approve
