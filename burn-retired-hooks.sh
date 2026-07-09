#!/usr/bin/env bash
# burn-retired-hooks.sh — remove the retired offload/coordination machinery.
#
# OPERATOR-RUN ONLY: guard-hook-immutable.sh (directive 2026-07-04) blocks
# agents from creating, editing, or deleting hooks — including this deletion.
# Prepared by the agent 2026-07-07 on operator request ("burn them with fire");
# scope confirmed via interview: retired cluster + coordination ownership helpers.
#
# Verified before writing this script: NONE of these are registered in
# ~/.claude/settings.json hooks — they are dead files. The active hook set
# (guard-*, session-*, rtk-rewrite, worktree-jail, notify, captures, waf
# sanitizer, frontload-reminder, herdr, relay-poll) is untouched.
#
# After running: chezmoi status should no longer list these under .claude/,
# and `git -C ~/projects/todie/dotfiles status` will show the source deletions
# to commit.
set -euo pipefail

BURN_HOOKS=(
  agent-auto-register.sh      # agent-team auto-registration (retired multi-agent gen)
  agent-offload-shim.sh       # local-LLM offload (retired system, global CLAUDE.md)
  webfetch-offload-shim.sh    # local-LLM offload (retired)
  agent-preamble-check.sh     # worker preamble enforcement (retired)
  worker-lifecycle.sh         # worker fleet lifecycle (retired)
  file-lock-gate.sh           # cross-agent file locking (retired; worktrees instead)
  role-boundary-gate.sh       # worker role fencing (retired)
  hypervisor-preflight.sh     # hypervisor/fleet preflight (retired)
  engram-start.sh.disabled    # already disabled
  coord-own                   # coordination ownership helper (burn before first apply)
  guard-coord-ownership.sh    # coordination ownership gate (burn before first apply)
)

echo "== live files =="
for h in "${BURN_HOOKS[@]}"; do rm -fv "$HOME/.claude/hooks/$h"; done

echo "== chezmoi source (prevents resurrection on apply) =="
SRC="$HOME/projects/todie/dotfiles/home"
for h in "${BURN_HOOKS[@]}"; do rm -fv "$SRC/dot_claude/hooks/executable_$h"; done

echo "== verify: no settings.json references (expect 'clean') =="
if grep -nE "$(IFS='|'; echo "${BURN_HOOKS[*]}")" "$HOME/.claude/settings.json"; then
  echo "WARNING: references found above — remove them from settings.json hooks[]" >&2
  exit 1
else
  echo "clean — nothing registered, no deregistration needed"
fi

echo "Done. Review 'git -C ~/projects/todie/dotfiles status' and commit the deletions."
