#!/usr/bin/env bash
# guard-main-checkout.sh — PreToolUse hook. Jails the MAIN session out of the
# shared unsigned-paas checkout: blocks writes + git-mutations whose target is
# the MAIN worktree, forcing all work into a dedicated worktree. Complements
# worktree-jail.sh (which jails SUBAGENTS into their worktree).
#
# Operator rule 2026-06-13: the shared ~/projects/unsigned-paas checkout is a
# REFERENCE, not a workspace. Fails OPEN on any ambiguity. Bypass:
# `# allow-main-checkout` in a Bash command, or GUARD_MAIN_CHECKOUT_BYPASS=1.
#
# Detection is SEGMENT- and TARGET-aware (rewritten 2026-06-13): a command is
# only blocked when a pipeline segment is literally a `git <mutating-verb>`
# invocation whose target tree (honoring -C/--git-dir, else the effective cwd)
# is the main checkout. Read-only git (log/diff/show/status/...), `gh`, and a
# bare `git` substring inside grep/sed/gh arguments no longer false-positive.

set -uo pipefail
INPUT=$(cat 2>/dev/null) || exit 0
approve() { echo '{"decision":"approve"}'; exit 0; }
block()   { jq -n --arg r "$1" '{decision:"block", reason:$r}' 2>/dev/null || printf '{"decision":"block","reason":"%s"}' "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || exit 0
[ "${GUARD_MAIN_CHECKOUT_BYPASS:-0}" = "1" ] && approve

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // .tool_input.cwd // empty' 2>/dev/null)

# resolve whether a path sits in the MAIN worktree of the unsigned-paas repo
# (git-dir == git-common-dir) vs a linked worktree. echoes "MAIN" / "" .
main_worktree_of_unsigned() {
  local p="$1" gdir common
  [ -n "$p" ] || return 0
  [ -e "$p" ] || p=$(dirname "$p")
  [ -d "$p" ] || return 0
  common=$(git -C "$p" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  case "$common" in */unsigned-paas/.git*) ;; *) return 0 ;; esac
  gdir=$(git -C "$p" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 0
  [ "$gdir" = "$common" ] && echo MAIN
}

case "$TOOL" in
  Edit|Write|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    [ -z "$FP" ] && approve
    case "$FP" in /*) ;; *) approve ;; esac
    if [ "$(main_worktree_of_unsigned "$FP")" = MAIN ]; then
      block "guard-main-checkout: refusing a write into the SHARED main checkout.
  target: $FP

The shared ~/projects/unsigned-paas checkout is a reference, not a workspace.
Work in a worktree:  git worktree add /tmp/wt-<name> <branch> && cd /tmp/wt-<name>
Override (rare): out of band, or set GUARD_MAIN_CHECKOUT_BYPASS=1."
    fi
    approve
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [ -z "$CMD" ] && approve
    printf '%s' "$CMD" | grep -q '# *allow-main-checkout' && approve

    # Effective cwd: honor a leading `cd <path>` (first one wins; multi-cd
    # commands are rare and fall back to fail-open via the per-segment check).
    # Handles absolute (/x), home (~ or ~/x) AND relative (x/y) targets — a
    # ~-relative cd previously fell through to $CWD and false-blocked commits run
    # in another repo via `cd ~/projects/<other>` (2026-06-15).
    ecwd="$CWD"
    cd_target=$(printf '%s' "$CMD" | grep -oE 'cd[[:space:]]+["'"'"']?[^[:space:]"'"'"';|&]+' | head -1 | sed -E 's/^cd[[:space:]]+["'"'"']?//' || true)
    if [ -n "$cd_target" ]; then
      case "$cd_target" in
        '~')    ecwd="$HOME" ;;
        '~/'*)  ecwd="$HOME/${cd_target#'~/'}" ;;
        /*)     ecwd="$cd_target" ;;
        *)      ecwd="${CWD:+$CWD/}$cd_target" ;;
      esac
    fi

    # Scan each ;/|/&&/|| segment. Block only a real `git <mutating-verb>`
    # invocation whose target tree is the MAIN checkout.
    blocked_target=""
    segs=$(printf '%s' "$CMD" | sed -E 's/(\|\||&&|[;|&])/\n/g')
    while IFS= read -r seg; do
      # ltrim, then strip leading VAR=value assignments (env prefixes).
      seg="${seg#"${seg%%[![:space:]]*}"}"
      seg=$(printf '%s' "$seg" | sed -E "s/^([A-Za-z_][A-Za-z0-9_]*=([^[:space:]\"']*|\"[^\"]*\"|'[^']*')[[:space:]]+)+//")
      # The segment must BE a git invocation (first token == git).
      case "$seg" in git|git\ *) ;; *) continue ;; esac
      rest=$(printf '%s' "$seg" | sed -E 's/^git[[:space:]]+//')
      tdir="$ecwd"
      # Walk git global options; -C / --git-dir redirect the target tree.
      while :; do
        case "$rest" in
          -C[[:space:]]*)   tdir=$(printf '%s' "$rest" | awk '{print $2}'); rest=$(printf '%s' "$rest" | sed -E 's/^-C[[:space:]]+[^[:space:]]+[[:space:]]*//') ;;
          --git-dir=*)      tdir=$(printf '%s' "$rest" | sed -E 's/^--git-dir=([^[:space:]]+).*/\1/'); rest=$(printf '%s' "$rest" | sed -E 's/^--git-dir=[^[:space:]]+[[:space:]]*//') ;;
          -c[[:space:]]*)   rest=$(printf '%s' "$rest" | sed -E 's/^-c[[:space:]]+[^[:space:]]+[[:space:]]*//') ;;
          --work-tree=*|--namespace=*) rest=$(printf '%s' "$rest" | sed -E 's/^--[^[:space:]]+[[:space:]]*//') ;;
          -*)               rest=$(printf '%s' "$rest" | sed -E 's/^-[^[:space:]]+[[:space:]]*//') ;;
          *) break ;;
        esac
      done
      verb=$(printf '%s' "$rest" | awk '{print $1}')
      mut=0
      # Only WORKING-TREE / branch-state mutations of the main checkout are
      # blocked. `git worktree add|remove|move|prune` is intentionally NOT here:
      # creating/managing linked worktrees from the main repo is the sanctioned
      # escape this hook tells you to use — it does not mutate main's tree.
      case "$verb" in
        commit|checkout|switch|cherry-pick|rebase|merge|reset|am|restore) mut=1 ;;
      esac
      [ "$mut" = 1 ] || continue
      if [ "$(main_worktree_of_unsigned "$tdir")" = MAIN ]; then blocked_target="$tdir"; break; fi
    done <<EOF
$segs
EOF

    if [ -n "$blocked_target" ]; then
      block "guard-main-checkout: refusing a git mutation in the SHARED main checkout.
  target: $blocked_target  (main worktree — a reference, not a workspace)

Take a worktree and work there:
  git worktree add -b <branch> /tmp/wt-<name> origin/main
  git worktree add /tmp/wt-<name> <existing-branch>
  cd /tmp/wt-<name> && <your git op>
Override (rare, intentional): append  # allow-main-checkout"
    fi
    approve
    ;;
  *) approve ;;
esac
