#!/usr/bin/env bash
# hypervisor-preflight.sh — PreToolUse hook with 3 matchers (TOD-483).
#
# Catches recurring hypervisor-mode violations at PreToolUse time:
#
#   1. Agent dispatch without preflight checklist in the prompt.
#   2. Bulk mcp__claude_ai_Linear__save_issue calls that should use the
#      /linear-file-spec skill.
#   3. Edit/Write targeting ~/.claude/* without holding the coord lock
#      `claude-config`.
#
# Input:  JSON blob on stdin describing the tool call.
# Output: JSON verdict — {"decision":"approve"} or {"decision":"block","reason":"..."}
# Exit:   0 always — decision is in JSON.
#
# Each matcher has a bypass mechanism (see per-matcher notes below).
#
# State: bulk save_issue counter is persisted at
#        /tmp/claude-coord/hypervisor-stats/save_issue_history
# as JSONL of {ts, session_id}. Entries older than 10 min are pruned on read.

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

approve() { echo '{"decision":"approve"}'; exit 0; }
block()   { local reason="$1"; jq -n --arg r "$reason" '{decision:"block", reason:$r}'; exit 0; }
warn()    { local msg="$1"; jq -n --arg m "$msg" '{decision:"approve", systemMessage:$m}'; exit 0; }

# ─── Matcher 1: Agent dispatch ───────────────────────────────────────────────
if [ "$TOOL_NAME" = "Agent" ]; then
    PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null)
    SUBAGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)

    # Bypass: explicit skip directive on first ~300 chars (preflight, preamble, or research).
    if echo "$PROMPT" | head -c 300 | grep -qE "^#[[:space:]]*(preflight|preamble|research):[[:space:]]*(skip|true)"; then
        approve
    fi

    # Bypass: short-form agents (≤500 chars) — not worth the overhead
    if [ "${#PROMPT}" -le 500 ]; then
        approve
    fi

    # Bypass: known research-only subagent types — they don't touch code.
    case "$SUBAGENT" in
        Explore|Plan|claude-code-guide) approve ;;
        rust-skills:*|claude-md-management:*|claude-code-setup:*) approve ;;
    esac

    # Check for the 5 preflight checklist items. Accept any synonym that shows
    # the hypervisor thought about each concern — not strict keyword match.
    missing=()
    echo "$PROMPT" | grep -qiE "worktree|git[[:space:]]+status|clean[[:space:]]+tree" \
        || missing+=("worktree-clean")
    echo "$PROMPT" | grep -qiE "sibling|other[[:space:]]+worker|collision|peer|coord[[:space:]]+peers" \
        || missing+=("sibling-collision-check")
    echo "$PROMPT" | grep -qiE "scope|bound|<[[:space:]]*500|under[[:space:]]+[0-9]+[[:space:]]+(line|loc)|small|narrow" \
        || missing+=("scope-bound")
    echo "$PROMPT" | grep -qiE "TOD-[0-9]+|prereq|depend|blocked[[:space:]]+by|relates[[:space:]]+to" \
        || missing+=("prereq-tickets")
    echo "$PROMPT" | grep -qiE "coord|session|~/\.claude/bin/coord|sha:|pinned" \
        || missing+=("coord-sha-pinned")

    if [ "${#missing[@]}" -ge 3 ]; then
        # 3+ missing: refuse hard. 1-2 missing: warn only.
        block "hypervisor-preflight: Agent prompt is missing ${#missing[@]} of 5 preflight items: ${missing[*]}. Fix the prompt to address each or add '# preflight: skip' on the first line for genuinely non-code research agents."
    elif [ "${#missing[@]}" -ge 1 ]; then
        warn "hypervisor-preflight: Agent prompt missing ${#missing[@]} preflight items: ${missing[*]}. (not blocked — 3+ missing would block)"
    fi
    approve
fi

# ─── Matcher 2: Linear save_issue rate-limit + title-dedup ───────────────────
if [ "$TOOL_NAME" = "mcp__claude_ai_Linear__save_issue" ]; then
    # Bypass: explicit skip directive in the title or description
    TITLE=$(echo "$INPUT" | jq -r '.tool_input.title // .tool_input.params.title // empty' 2>/dev/null)
    DESC=$(echo "$INPUT" | jq -r '.tool_input.description // .tool_input.params.description // empty' 2>/dev/null)
    if echo "$TITLE $DESC" | grep -qF "# bulk-file-spec: skip"; then
        approve
    fi

    # Normalize the title for dedup (lowercase, strip punctuation, collapse
    # whitespace). Hash so we don't leak full titles in /tmp.
    title_key=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | \
        tr -cd 'a-z0-9 ' | tr -s ' ' | sed 's/^ //; s/ $//' | sha256sum | cut -c1-16)

    stats_dir="/tmp/claude-coord/hypervisor-stats"
    mkdir -p "$stats_dir"
    history="$stats_dir/save_issue_history"
    now=$(date +%s)
    cutoff=$(( now - 600 ))  # 10 minutes

    sid="${SESSION_ID:-$(~/.claude/bin/coord status 2>/dev/null | awk '/^session_id:/ {print $2; exit}' || echo unknown)}"

    # Prune stale records BEFORE dedup check (so old dup titles don't block us)
    if [ -f "$history" ]; then
        tmp=$(mktemp)
        awk -v cutoff="$cutoff" -F'[:,]' '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /"ts"/) { n = $(i+1); gsub(/[^0-9]/, "", n); break }
                }
                if (n >= cutoff) print $0
            }
        ' "$history" > "$tmp" && mv "$tmp" "$history"
    fi

    # Dedup: same normalized title filed in the past 10min → block.
    # Only updates (save_issue with an `id` field) are exempt — those are
    # legitimate state transitions.
    has_id=$(echo "$INPUT" | jq -r '.tool_input.id // .tool_input.params.id // empty' 2>/dev/null)
    if [ -z "$has_id" ] && [ -f "$history" ] && grep -qF "\"title_key\":\"$title_key\"" "$history"; then
        block "hypervisor-preflight: duplicate save_issue title detected (filed within 10min window). Add '# bulk-file-spec: skip' to override, or use save_issue with an id to update the existing ticket."
    fi

    # Classify the call: "filing-shaped" (creates a new ticket OR edits the
    # body of an existing one — these are the costly operations the
    # /linear-file-spec skill exists to batch) vs "field-touch" (id-update
    # of state, parentId, milestone, labels, etc — cheap atomic flips that
    # legitimately come in bursts during grooming and shouldn't be rate-
    # limited as if they were "filing"). Only filing-shaped calls increment
    # the per-session counter and trigger the block at 5+.
    is_filing="0"
    if [ -z "$has_id" ] || [ -n "$TITLE" ] || [ -n "$DESC" ]; then
        is_filing="1"
    fi

    # Record this call for future-check (filing vs touch tagged so future
    # readers can audit the distinction).
    echo "{\"ts\":$now,\"session_id\":\"$sid\",\"title_key\":\"$title_key\",\"filing\":$is_filing}" >> "$history"

    # Count only filing-shaped calls toward the rate-limit threshold.
    count=$(grep -F "\"session_id\":\"$sid\"" "$history" | grep -cF '"filing":1' || true)

    # Check for the linear-file-spec skill
    has_skill=0
    [ -d "$HOME/.claude/skills/linear-file-spec" ] || [ -f "$HOME/.claude/skills/linear-file-spec/SKILL.md" ] \
        && has_skill=1

    if [ "$count" -ge 5 ] && [ "$has_skill" = "1" ]; then
        block "hypervisor-preflight: 5th mcp__claude_ai_Linear__save_issue call in 10min — use /linear-file-spec instead (bulk ticket filing). Add '# bulk-file-spec: skip' to title or description to override."
    elif [ "$count" -ge 3 ] && [ "$has_skill" = "1" ]; then
        warn "hypervisor-preflight: nudge — ${count} save_issue calls in 10min. /linear-file-spec skill exists for bulk filing (60-70% token reduction). Will block at 5."
    fi
    approve
fi

# ─── Matcher 3: ~/.claude/* edit/write requires claude-config lock ───────────
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

    # Only gate files under ~/.claude/{settings,hooks,skills,bin,templates}
    case "$FILE_PATH" in
        "$HOME/.claude/settings"*|"$HOME/.claude/hooks"/*|"$HOME/.claude/skills"/*|\
        "$HOME/.claude/bin"/*|"$HOME/.claude/templates"/*|\
        /home/*/.claude/settings*|/home/*/.claude/hooks/*|/home/*/.claude/skills/*|\
        /home/*/.claude/bin/*|/home/*/.claude/templates/*)
            ;;
        *) approve ;;
    esac

    # ─── SOFTENED to warn-only (CER-1114) ────────────────────────────────────
    # The claude-config lock gate was structurally broken: `coord lock` writes to
    # the redis backend (coord default) while this hook read the lock holder from
    # the filesystem (/tmp/claude-coord/locks/claude-config/owner) — and FS writes
    # are NO-OPs in redis mode. So the gate was unsatisfiable via the documented
    # command AND bypassable by a bare `touch`: friction with zero guarantee.
    # Re-arm as a hard block once coord backend-coherence is fixed (CER-1114).
    warn "hypervisor-preflight: editing ${FILE_PATH#$HOME/} under ~/.claude/ — coord-lock enforcement is SOFTENED to warn-only pending the coord backend-coherence fix (CER-1114). Proceeding without a lock; if a reverie peer is active, coordinate manually."
fi

# Unmatched tool — pass through
approve
