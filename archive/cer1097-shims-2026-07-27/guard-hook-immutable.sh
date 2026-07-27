#!/usr/bin/env bash
# guard-hook-immutable.sh — hooks are OPERATOR-IMMUTABLE.
#
# Operator directive 2026-07-04, verbatim: "From now on, if a process wants
# to update a hook, tell it to fuck off." Context: a session self-authored a
# global enforcement hook and iterated on it live, three edits in minutes.
# Guardrails that agents can rewrite are not guardrails.
#
# Blocks any agent/tool mutation of:
#   - ~/.claude/hooks/** and any .claude/hooks/** (the hook scripts)
#   - ~/.claude/settings.json / settings.local.json and project
#     .claude/settings*.json (the hook wiring lives there)
# via Write/Edit tools or Bash mutation (redirect, sed -i, tee, cp, mv, rm,
# chmod, ln, truncate, install).
#
# There is NO agent override marker — that would be a hook change policy an
# agent could invoke. Hook changes are made by the operator, by hand, or in a
# session where the operator explicitly dictates the change AND disables this
# guard himself for that one action (claude --settings, /hooks UI, or manual
# edit in his editor).
set -uo pipefail

IN=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$IN" 2>/dev/null) || exit 0

deny() {
  echo "FUCK OFF: hooks are operator-immutable (directive 2026-07-04). No agent creates, edits, rewires, or deletes hooks — not even to 'improve' them. Surface the proposed change to the operator instead; he makes hook changes by hand." >&2
  exit 2
}

is_protected_path() {
  case "$1" in
    */.claude/hooks/*|*/.claude/settings.json|*/.claude/settings.local.json) return 0 ;;
  esac
  return 1
}

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    FP=$(jq -r '.tool_input.file_path // empty' <<<"$IN" 2>/dev/null)
    [ -n "$FP" ] && is_protected_path "$FP" && deny
    ;;
  Bash)
    CMD=$(jq -r '.tool_input.command // empty' <<<"$IN" 2>/dev/null)
    [ -n "$CMD" ] || exit 0
    echo "$CMD" | grep -qE '\.claude/(hooks/|settings(\.local)?\.json)' || exit 0
    # Mutation indicators; plain reads (cat/grep/ls/diff/jq file) pass.
    echo "$CMD" | grep -qE '(>>?|(^|[[:space:]&|;(])(sed[[:space:]]+(-[^i[:space:]]+[[:space:]]+)*-i|tee[[:space:]]|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|chmod[[:space:]]|chown[[:space:]]|ln[[:space:]]|truncate[[:space:]]|install[[:space:]]|python3?[[:space:]]|perl[[:space:]]))' || exit 0
    deny
    ;;
esac
exit 0
