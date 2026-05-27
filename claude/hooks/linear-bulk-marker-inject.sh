#!/usr/bin/env bash
# linear-bulk-marker-inject.sh — PreToolUse hook on mcp__claude_ai_Linear__save_issue.
#
# When the current session emits >= 4 save_issue calls in a 10-minute window,
# auto-append "# bulk-file-spec: skip" to the outgoing description field so
# the downstream hypervisor-preflight rate-limit guard treats the burst as an
# intentional bulk-file operation rather than fanning out individual prompts.
#
# Per proposal 4.1 in ~/configs/skill-proposals/2026-05-27-session-lessons.md.
#
# Protocol: read JSON from stdin, emit the PreToolUse hookSpecificOutput
# verdict — `allow` with optional `updatedInput` rewrite — on stdout.
# Always exits 0; logic decisions are in the JSON.
#
# State: /tmp/claude-linear-save-issue.log — JSONL of {ts} entries pruned to
# the last 10 minutes on every invocation.

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "linear-bulk-marker-inject"

INPUT=$(safe_read_stdin)
TOOL_NAME=$(json_field "$INPUT" '.tool_name')

# Only act on the target tool — every other call passes straight through.
if [ "$TOOL_NAME" != "mcp__claude_ai_Linear__save_issue" ]; then
    hook_allow
fi

LOG="/tmp/claude-linear-save-issue.log"
NOW=$(date +%s)
CUTOFF=$(( NOW - 600 ))  # 10-minute rolling window

# Prune stale rows BEFORE counting so we don't fire on history that has aged out.
if [ -f "$LOG" ]; then
    tmp=$(mktemp)
    awk -v cutoff="$CUTOFF" -F'[:,}]' '
        {
            ts = 0
            for (i = 1; i <= NF; i++) {
                if ($i ~ /"ts"/) { v = $(i+1); gsub(/[^0-9]/, "", v); ts = v + 0; break }
            }
            if (ts >= cutoff) print $0
        }
    ' "$LOG" > "$tmp" && mv "$tmp" "$LOG"
fi

# Count remaining (= calls inside the window, this call not yet recorded).
PRIOR=0
if [ -f "$LOG" ]; then
    PRIOR=$(wc -l < "$LOG" | tr -d ' ')
fi

# Always log this call AFTER reading the count — the threshold is "≥4 prior".
echo "{\"ts\":${NOW}}" >> "$LOG"

# Below threshold: pass the payload through unchanged.
if [ "$PRIOR" -lt 4 ]; then
    hook_allow
fi

# At/over threshold: inject the marker into the description field if missing.
# Linear save_issue payloads can carry either .tool_input.description or
# .tool_input.params.description; check both, mutate whichever exists, and
# fall back to .tool_input.description if neither is set.
DESC=$(json_field "$INPUT" '.tool_input.description')
PARAMS_DESC=$(json_field "$INPUT" '.tool_input.params.description')

MARKER="# bulk-file-spec: skip"

# If marker is already present anywhere in description, no-op.
if echo "${DESC}${PARAMS_DESC}" | grep -qF "$MARKER"; then
    hook_allow
fi

# Decide which path to mutate.
if [ -n "$PARAMS_DESC" ]; then
    NEW_INPUT=$(echo "$INPUT" | jq --arg m "$MARKER" \
        '.tool_input.params.description = (.tool_input.params.description + "\n\n" + $m)')
elif [ -n "$DESC" ]; then
    NEW_INPUT=$(echo "$INPUT" | jq --arg m "$MARKER" \
        '.tool_input.description = (.tool_input.description + "\n\n" + $m)')
else
    # No description field at all — create one carrying just the marker so the
    # downstream rate-limit guard sees the override.
    NEW_INPUT=$(echo "$INPUT" | jq --arg m "$MARKER" \
        '.tool_input.description = $m')
fi

UPDATED=$(echo "$NEW_INPUT" | jq '.tool_input')
hook_rewrite "$UPDATED"
