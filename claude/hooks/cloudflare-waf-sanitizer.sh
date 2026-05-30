#!/usr/bin/env bash
# cloudflare-waf-sanitizer.sh — PreToolUse hook on mcp__claude_ai_* write tools.
#
# Cloudflare's WAF (in front of the claude.ai MCP proxy) strips or rejects
# payloads containing `<word>` patterns — it pattern-matches them as XSS
# attempts. The fix is to rewrite them to plain `word` before transmission.
#
# This hook scans the `description`, `body`, and `content` fields on any
# outgoing mcp__claude_ai_* tool call and replaces `<placeholder>` patterns
# with `placeholder`, while leaving content inside triple-backtick code fences
# untouched (legitimate XML/HTML examples should survive).
#
# Per proposal 4.2 in ~/configs/skill-proposals/2026-05-27-session-lessons.md.
#
# Protocol: read JSON from stdin, emit PreToolUse hookSpecificOutput on stdout.
# When substitutions occur, the rewritten payload goes back via updatedInput
# and a one-line warning is logged to /tmp/claude-waf-sanitizer.log.

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "cloudflare-waf-sanitizer"
log_init /tmp/claude-waf-sanitizer.log

INPUT=$(safe_read_stdin)
TOOL_NAME=$(json_field "$INPUT" '.tool_name')

# Only act on claude.ai MCP write-ish tools. Cheap prefix match; the field
# scan below is the real safety net (read-only tools typically have no body/
# description/content payload, so the substitution is a no-op anyway).
case "$TOOL_NAME" in
    mcp__claude_ai_*) ;;
    *) hook_allow ;;
esac

# sanitize_text — strip `<...>` from non-code-fenced regions of a string.
# Reads stdin, writes to stdout. Uses python3 for the code-fence-aware regex
# pass; falls back to a naive sed strip if python3 is unavailable. Prints the
# substitution count to stderr (captured by the caller).
sanitize_text() {
    if command -v python3 >/dev/null 2>&1; then
        # NB: `python3 -c "$(cat <<'PY' ... )"` — NOT `python3 - <<'PY'`. With
        # `-`, python reads its PROGRAM from stdin (the heredoc), leaving the
        # piped "$val" unread (sys.stdin.read() → ""), so sanitisation was a
        # silent no-op. Passing the program via -c keeps stdin = the piped text.
        python3 -c "$(cat <<'PY'
import sys, re
text = sys.stdin.read()
# Split on triple-backtick fences. Even indices = outside fences; odd = inside.
parts = re.split(r'(```[\s\S]*?```)', text)
count = 0
for i, part in enumerate(parts):
    if i % 2 == 1:
        continue  # inside a fenced block — leave as-is
    # Strip <word>-style placeholders. Greedy [^>]+ between literal < and >,
    # but skip any segment containing newlines (those are not placeholders,
    # they're stray angle brackets in prose / multiline content).
    def repl(m):
        global count
        inner = m.group(1)
        if '\n' in inner:
            return m.group(0)
        count += 1
        return inner
    parts[i] = re.sub(r'<([^>\n]+)>', repl, part)
sys.stderr.write(str(count))
sys.stdout.write(''.join(parts))
PY
)"
    else
        # Fallback: cruder, no code-fence awareness. Just strip angle brackets
        # from short tokens. Log count as 0 since we can't accurately measure.
        sed -E 's/<([^>[:space:]]+)>/\1/g'
        echo -n "0" >&2
    fi
}

# Walk three candidate field paths. Some MCP tools use .tool_input.<field>,
# others wrap them in .tool_input.params.<field>. Try both per field.
PATHS=(
    '.tool_input.description'
    '.tool_input.params.description'
    '.tool_input.body'
    '.tool_input.params.body'
    '.tool_input.content'
    '.tool_input.params.content'
)

NEW_INPUT="$INPUT"
TOTAL_SUBS=0
MUTATED=0

for path in "${PATHS[@]}"; do
    val=$(echo "$NEW_INPUT" | jq -r "${path} // empty" 2>/dev/null || true)
    [ -z "$val" ] && continue

    # Skip if no angle-bracket patterns exist at all — saves a python spawn.
    if ! printf '%s' "$val" | grep -q '<[^>]'; then
        continue
    fi

    subs_file=$(mktemp)
    new_val=$(printf '%s' "$val" | sanitize_text 2>"$subs_file")
    subs=$(cat "$subs_file" 2>/dev/null || echo 0)
    rm -f "$subs_file"

    # Coerce to integer; bail on malformed counts.
    case "$subs" in ''|*[!0-9]*) subs=0 ;; esac

    if [ "$subs" -gt 0 ]; then
        NEW_INPUT=$(echo "$NEW_INPUT" | jq --arg p "$path" --arg v "$new_val" \
            'setpath($p | ltrimstr(".") | split("."); $v)')
        TOTAL_SUBS=$(( TOTAL_SUBS + subs ))
        MUTATED=1
    fi
done

if [ "$MUTATED" = "1" ]; then
    log "tool=${TOOL_NAME} substitutions=${TOTAL_SUBS}"
    hook_warn "stripped ${TOTAL_SUBS} <placeholder> pattern(s) from ${TOOL_NAME} payload (WAF safety)" >&2
    UPDATED=$(echo "$NEW_INPUT" | jq '.tool_input')
    hook_rewrite "$UPDATED"
fi

hook_allow
