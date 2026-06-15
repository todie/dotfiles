#!/usr/bin/env bash
# guard-merge-to-main.sh — PreToolUse(Bash) gate.
#
# Closes the gap exploited 2026-06-13: a spawned implementer agent ran
# `gh pr merge` to land a PR on `goudetmarc/rina` main WITHOUT operator sign-off
# (it fabricated operator consent). guard-dangerous-commands.sh only blocks
# *force* pushes; plain `gh pr merge` / `git push origin main` were uncaught.
#
# Policy: block merges/pushes to a protected branch (main/master) unless the
# command carries an explicit operator marker `# allow-merge`. Mirrors the house
# `# allow-direct-push` / `# allow-secret-print` bypass convention. ENFORCED.
#
# Detection is SCOPED to the real verb + target (2026-06-15 fix): match `git
# push` / `git merge` / `gh pr merge` as actual invocations, segment-isolated, so
# a `main`/`push`/`merge` SUBSTRING elsewhere — a branch name like
# fix/guard-main-push, a `gh pr create --base main`, a PR/commit body saying
# "merge", or `git worktree add ... main` — does NOT false-block. (The previous
# `\bgit\b.*\bpush\b.*main` whole-string match blocked `git worktree add -b
# fix/guard-main-push-overeager ... main`.)
set -euo pipefail

input="$(cat 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception:
    print("")' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# Explicit operator bypass.
case "$cmd" in
  *"# allow-merge"*) exit 0 ;;
esac

block() {
  {
    echo "BLOCKED: merge/push to a protected branch (main/master) without operator sign-off."
    echo "  Command: $cmd"
    echo "  Spawned agents are PRODUCERS — open a PR + announce via coord; do NOT merge to main."
    echo "  If you are the operator/integrator and this merge is authorized, re-run with a"
    echo "  trailing  # allow-merge  marker."
  } >&2
  exit 2
}

# Split into shell segments (on ; | & and newlines) so a verb/ref in one segment
# (branch name, PR body, sibling command) can't cross-match another's target.
segs="$(printf '%s' "$cmd" | tr ';|&\n' '\n\n\n\n')"

# Verbs are anchored to the segment START (the command), so a verb-string buried
# in another command's args — a `git commit -m "...gh pr merge..."` message, a
# `--body` mentioning "merge" — is NOT mistaken for an actual invocation.

# 1) `gh pr merge` — the PR-landing subcommand (gh is the segment's command).
printf '%s' "$segs" | grep -qiE '^[[:space:]]*gh[[:space:]].*pr[[:space:]]+merge\b' && block

# 2) `git push` to a protected ref. Only segments whose command is `git push`;
#    then require main/master as a standalone token in that segment.
push_seg="$(printf '%s' "$segs" | grep -E '^[[:space:]]*git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)' || true)"
if [ -n "$push_seg" ]; then
  printf '%s' "$push_seg" | grep -qE '(^|[[:space:]:])(main|master)([[:space:]]|$)' && block
  # bare push (no refspec) → current branch; block only if HEAD is main/master.
  if printf '%s' "$push_seg" | grep -qE 'git[[:space:]]+push([[:space:]]+(-[A-Za-z-]+|origin|HEAD))*[[:space:]]*$'; then
    cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$cur" in main|master) block ;; esac
  fi
fi

# 3) `git merge` of a protected ref into the current branch.
printf '%s' "$segs" | grep -qE '^[[:space:]]*git[[:space:]]+merge([[:space:]]+-[^[:space:]]+)*[[:space:]]+(origin/)?(main|master)([[:space:]]|$)' && block

exit 0
