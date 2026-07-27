#!/usr/bin/env bash
# Splice the canonical guard wiring into ~/.claude/settings.json (CER-1741).
#
# settings.json is chezmoi-ignored because Claude Code rewrites it in place.
# Rather than fight that, this owns only the guard subset: it reads
# ~/.claude/guard-wiring.json and ensures each (matcher, hook) pair is present
# in .hooks.PreToolUse, preserving every other key untouched.
#
# ADDITIVE ONLY. It never removes an entry. Guards are the only thing binding
# agents that run with --dangerously-skip-permissions, so a wiring mechanism
# that can subtract is one that can silently disarm a host — which is exactly
# what happened in CER-1743. Removing a guard stays a deliberate manual act.
#
# Set GUARD_WIRING_DRY_RUN=1 to print what would change and exit.

set -uo pipefail

SETTINGS="${GUARD_WIRING_SETTINGS:-$HOME/.claude/settings.json}"
MANIFEST="${GUARD_WIRING_MANIFEST:-$HOME/.claude/guard-wiring.json}"
HOOKS_DIR="${GUARD_WIRING_HOOKS_DIR:-$HOME/.claude/hooks}"
DRY="${GUARD_WIRING_DRY_RUN:-0}"

command -v jq >/dev/null 2>&1 || { echo "guard-wiring: jq not found, skipping" >&2; exit 0; }
[ -f "$MANIFEST" ] || { echo "guard-wiring: no manifest at $MANIFEST, skipping" >&2; exit 0; }
[ -f "$SETTINGS" ] || { echo "guard-wiring: no settings at $SETTINGS, skipping" >&2; exit 0; }

# A guard that is wired but absent from disk is a silent no-op, so only wire
# hooks that actually exist on this host. Missing ones are reported, not
# invented.
added=0 missing=0
tmp="$(mktemp "${TMPDIR:-/tmp}/guard-wiring.XXXXXX")" || exit 0
trap 'rm -f "$tmp"' EXIT
cp "$SETTINGS" "$tmp" || exit 0

while IFS=$'\t' read -r matcher hook; do
  [ -n "$matcher" ] || continue
  if [ ! -f "$HOOKS_DIR/$hook" ]; then
    echo "guard-wiring: $hook not present on this host — not wiring" >&2
    missing=$((missing + 1))
    continue
  fi
  cmd="$HOOKS_DIR/$hook"

  # Already wired for this matcher? Compare on the hook's basename with the
  # home prefix normalised: an existing entry may spell the path as
  # "~/.claude/hooks/x.sh", "$HOME/.claude/hooks/x.sh" or fully expanded, and a
  # literal string compare would treat those as different and wire a duplicate.
  if jq -e --arg m "$matcher" --arg h "$hook" '
      (.hooks.PreToolUse // [])
      | any(
          .matcher == $m
          and ((.hooks // []) | any(
                 (.command // "")
                 | gsub("^~/|^\\$HOME/|^\\$\\{HOME\\}/"; "")
                 | split("/") | last
                 | . == $h))
        )' "$tmp" >/dev/null 2>&1; then
    continue
  fi

  echo "guard-wiring: + $hook (matcher $matcher)"
  added=$((added + 1))
  [ "$DRY" = "1" ] && continue

  out="$(jq --arg m "$matcher" --arg c "$cmd" '
    .hooks //= {} |
    .hooks.PreToolUse //= [] |
    .hooks.PreToolUse |= (
      if any(.matcher == $m) then
        map(if .matcher == $m
            then .hooks = ((.hooks // []) + [{type:"command", command:$c}])
            else . end)
      else
        . + [{matcher:$m, hooks:[{type:"command", command:$c}]}]
      end
    )' "$tmp")" || { echo "guard-wiring: jq failed, aborting with no changes" >&2; exit 0; }
  printf '%s' "$out" > "$tmp" || exit 0
done < <(jq -r '.shared.PreToolUse[] | "\(.matcher)\t\(.hook)"' "$MANIFEST" 2>/dev/null)

if [ "$added" -eq 0 ]; then
  echo "guard-wiring: all canonical guards already wired${missing:+ (${missing} absent from disk)}"
  exit 0
fi

[ "$DRY" = "1" ] && { echo "guard-wiring: dry run, $added change(s) not applied"; exit 0; }

# Validate before replacing the file that boots the harness.
jq -e . "$tmp" >/dev/null 2>&1 || { echo "guard-wiring: result is not valid JSON, aborting" >&2; exit 0; }
cp "$SETTINGS" "$SETTINGS.guard-wiring.bak" 2>/dev/null || true
cat "$tmp" > "$SETTINGS" && echo "guard-wiring: wired $added guard(s); previous file at $SETTINGS.guard-wiring.bak"
