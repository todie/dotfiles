#!/usr/bin/env bash
# session-bootstrap-engram-drift.sh — SessionStart hook.
#
# Invokes the engram-drift-check skill (proposal 2.5) in dry-run mode for the
# current project, surfacing any contradictions between engram observations
# and ground truth (Linear team keys, project names, file paths, etc.) as a
# <system-reminder>-shaped block at the top of the session context.
#
# Non-blocking: if the skill is missing, errors, or finds nothing, exit 0
# silently. The goal is awareness, not gating.
#
# Per proposal 4.3 in ~/configs/skill-proposals/2026-05-27-session-lessons.md.
#
# NOTE: the engram-drift-check skill is being built in parallel; this hook
# references it by path and degrades gracefully when the skill is missing.

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "engram-drift"

# Resolve the current project from cwd; skill needs --project to scope the
# observation pull.
IFS='|' read -r PROJECT _PROJ_HASH _REPO_ROOT <<< "$(project_info "$PWD")"

# Skill location candidates (skill loader looks in both global and project-
# local trees). First existing wins; if none, we silently exit.
SKILL_CANDIDATES=(
    "$HOME/.claude/skills/engram-drift-check/SKILL.md"
    "$HOME/.claude/skills/engram-drift-check/skill.md"
    "$HOME/.claude/skills/engram-drift-check.sh"
    "$HOME/.agents/skills/engram-drift-check/SKILL.md"
)

SKILL_PATH=""
for candidate in "${SKILL_CANDIDATES[@]}"; do
    if [ -e "$candidate" ]; then
        SKILL_PATH="$candidate"
        break
    fi
done

if [ -z "$SKILL_PATH" ]; then
    # Skill not yet installed — graceful no-op. Don't even emit a hook line
    # to keep startup output quiet for users who never wire this up.
    exit 0
fi

# Engram must be reachable for the skill to do anything useful. If the
# context endpoint is down, just exit — the regular session-bootstrap hook
# already reports engram health.
if ! http_ok "$ENGRAM_URL/health"; then
    exit 0
fi

# Run the drift check. The skill is expected to support:
#   --project <name>    scope the observation pull
#   --dry-run           never mutate engram from a bootstrap hook
#   --format json       structured contradictions on stdout
#
# If it's a .md skill (the SKILL.md convention used by ~/.claude/skills), we
# can't exec it directly — fall back to a CLI runner if one exists, else exit.
RUNNER=""
if [ -x "$HOME/.claude/bin/skill-run" ]; then
    RUNNER="$HOME/.claude/bin/skill-run"
elif [ -x "$HOME/.local/bin/skill-run" ]; then
    RUNNER="$HOME/.local/bin/skill-run"
fi

case "$SKILL_PATH" in
    *.sh)
        # Direct-executable skill — invoke straight.
        OUTPUT=$("$SKILL_PATH" --project "$PROJECT" --dry-run --format json 2>/dev/null || echo "")
        ;;
    *)
        # SKILL.md form — needs the runner. If no runner, we can't act.
        if [ -z "$RUNNER" ]; then
            exit 0
        fi
        OUTPUT=$("$RUNNER" engram-drift-check --project "$PROJECT" --dry-run --format json 2>/dev/null || echo "")
        ;;
esac

# No output, or output isn't valid JSON, or it reports zero contradictions —
# stay silent. The hook exists to surface drift, not announce its absence.
if [ -z "$OUTPUT" ]; then
    exit 0
fi

# Try to parse + count contradictions. The skill's exact schema is being
# defined in parallel; accept either {contradictions:[...]} or {drift:[...]}.
COUNT=$(echo "$OUTPUT" | jq -r '
    if type == "object" then
        (.contradictions // .drift // []) | length
    else 0 end
' 2>/dev/null || echo 0)

case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

if [ "$COUNT" = "0" ]; then
    exit 0
fi

# Surface as a system-reminder-shaped block so Claude reads it during session
# kickoff. Output goes to stdout — the session-bootstrap context channel.
hook_section "Engram Drift (${COUNT} contradiction(s))"
echo "<system-reminder>"
echo "engram-drift-check found ${COUNT} contradiction(s) for project=${PROJECT}."
echo "Treat any prior engram claims about these entities as STALE until reconfirmed."
echo ""
echo "$OUTPUT" | jq -r '
    (.contradictions // .drift // [])[] |
    "- " + (.claim // .observation // "?") +
    "  →  ground-truth: " + (.truth // .actual // "?") +
    (if .obs_id then "  (obs " + (.obs_id|tostring) + ")" else "" end)
' 2>/dev/null || echo "(could not parse contradiction list — raw output below)"

# If parsing failed, dump the first 20 lines of raw output for the user.
if ! echo "$OUTPUT" | jq -e '.' >/dev/null 2>&1; then
    echo ""
    echo "Raw skill output (truncated):"
    echo "$OUTPUT" | head -20
fi
echo "</system-reminder>"

exit 0
