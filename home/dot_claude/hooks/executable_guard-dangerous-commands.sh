#!/usr/bin/env bash
# guard-dangerous-commands.sh — PreToolUse hook for Bash commands
# Exit 0 = allow, Exit 2 = block
# This catches patterns that slip through settings.json deny rules
# (e.g., piped commands, encoded strings, nested shells)
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# If jq fails or command is empty, allow (don't block on parse errors)
[ -z "$COMMAND" ] && exit 0

# PER-STATEMENT scanning. Split COMMAND on ; && || and newlines (NOT a single
# |, so pipelines like `curl … | bash` stay intact within a statement) and run
# each dangerous-op rule against its OWN statement. This stops cross-statement
# conflation that the prior whole-command scan produced:
#   - `rm -rf /tmp/x && echo /home/ctodie` no longer false-blocks (the rm and
#     the /home token are different statements),
#   - a stray `-f` or `main` in one statement can't trip the force/rm rule that
#     belongs to another,
#   - a `localhost` token in one statement can't disable the curl|interpreter
#     guard in a different statement (was a real fail-OPEN).
# The full AST/policy redesign (Phase 4) supersedes this interim parser.
PROT_DOT='(~|\$\{?HOME\}?|/home/ctodie)/\.(ssh|gpg|secrets|gitconfig)'
LOCAL_HOST='https?://([^/@[:space:]]*@)?(127\.0\.0\.1|0\.0\.0\.0|localhost|host\.docker\.internal|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)(:[0-9]+)?([/[:space:]]|$)'

scan_segment() {
  local seg="$1"

  # Destructive DB (DROP/TRUNCATE always; unqualified DELETE FROM = mass delete)
  if echo "$seg" | grep -qiE '(DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)|TRUNCATE\s+(TABLE\s+)?\S+)'; then
    echo "BLOCKED: Destructive database operation (DROP/TRUNCATE) detected. Use explicit confirmation." >&2; exit 2
  fi
  if echo "$seg" | grep -qiE 'DELETE\s+FROM\s+\S+' && ! echo "$seg" | grep -qiE 'DELETE\s+FROM\s+.*[^a-zA-Z_]WHERE[^a-zA-Z_]'; then
    echo "BLOCKED: Unqualified DELETE FROM (no WHERE) is a mass delete. Add a WHERE clause or confirm explicitly." >&2; exit 2
  fi

  # Force push to main/master — git + push + force-indicator + protected ref, ALL in this statement.
  if echo "$seg" | grep -qE '(^|[^[:alnum:]])git([[:space:]]|$)' \
     && echo "$seg" | grep -qE '(^|[^[:alnum:]])push([^[:alnum:]]|$)' \
     && echo "$seg" | grep -qE '(--force([^-[:alnum:]]|=|$)|--force-with-lease|(^|[[:space:]])-[a-zA-Z]*f([[:space:]]|$)|[[:space:]]\+(main|master|HEAD)([^[:alnum:]]|$))' \
     && echo "$seg" | grep -qE '(^|[^[:alnum:]_])(main|master)([^[:alnum:]_]|$)'; then
    echo "BLOCKED: Force push to main/master is not allowed." >&2; exit 2
  fi

  # Critical dotfile writes (redirect/tee/sed-i adjacent; cp/mv/install/rsync/sed-i dest = last token).
  if echo "$seg" | grep -qE "(>>?|tee([[:space:]]+-a)?|sed[[:space:]]+-i[^[:space:]]*)[[:space:]]*[\"']?${PROT_DOT}"; then
    echo "BLOCKED: Cannot write to critical dotfiles (.ssh, .gpg, .secrets, .gitconfig) via redirect/tee/sed -i." >&2; exit 2
  fi
  case "$seg" in
    *"cp "*|*"mv "*|*"install "*|*"rsync "*|*"sed -i"*|*"sed --in-place"*)
      _dst=$(printf '%s' "$seg" | awk '{print $NF}' | sed -E "s/^[\"']//; s/[\"']\$//")
      if printf '%s' "$_dst" | grep -qE "^${PROT_DOT}"; then
        echo "BLOCKED: Cannot write to critical dotfiles (.ssh, .gpg, .secrets, .gitconfig) as a copy/move/sed-i destination." >&2; exit 2
      fi ;;
  esac

  # Remote script piped to an interpreter — localhost carve-out scoped to THIS statement.
  if echo "$seg" | grep -qE '(curl|wget)\s.*\|\s*(bash|sh|zsh|python[0-9.]*|perl|ruby|node)' \
     && ! echo "$seg" | grep -qE "$LOCAL_HOST"; then
    echo "BLOCKED: Piping remote content to interpreter. Download first, review, then run." >&2; exit 2
  fi

  # Recursive deletion of home/root (rm + recursive flag + a home/root target; subdirs allowed).
  if echo "$seg" | grep -qE '(^|[^[:alnum:]_./-])rm([[:space:]]|$)' \
     && echo "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)' \
     && echo "$seg" | grep -qE '(^|[[:space:]])["'"'"']?(/|~|\$\{?HOME\}?|/home/ctodie|/root)/?["'"'"']?([[:space:]]|;|\||&|$)'; then
    echo "BLOCKED: Recursive deletion of home or root directory." >&2; exit 2
  fi
}

# Iterate statements (process substitution keeps the loop in this shell so a
# scan_segment `exit 2` blocks the whole command).
while IFS= read -r _seg; do
  [ -n "$_seg" ] && scan_segment "$_seg"
done < <(printf '%s\n' "$COMMAND" | sed -E 's/&&/\n/g; s/[|][|]/\n/g; s/;/\n/g')

# ─── Secret-leak prevention ──────────────────────────────────────────────────
# Origin: 2026-04-06 leak of ANTHROPIC_API_KEY via ${VAR:+yes}${VAR:-no} pattern.
# Hardened 2026-04-06 (after claude-secret-test agent review):
#   - SECRET_NAME end-anchored so KEYBOARD_LAYOUT / TOKENS_PROCESSED no longer
#     trip false positives (the secret keyword must be at the END of the name).
#   - All rules use grep -i so lowercase env vars (api_key, github_token) match.
#   - Sentinel check requires `# allow-secret-print` at END of a line so a
#     literal occurrence inside a string can't smuggle a bypass.
#   - /dev/tty test now actually opens it (not just stat-checks writability).
# Escape valve: append `# allow-secret-print` to a command line (at end-of-line)
# to bypass these rules when intentional.
SECRET_NAME='([A-Za-z_][A-Za-z0-9_]*)?(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CRED|PRIVATE|APIKEY)'
GUARD_LOG="$HOME/.claude/logs/secret-guard.log"

# Notify the human at their actual terminal so they can differentiate hook blocks
# from other failures. The (: > /dev/tty) test actually attempts a write, so it
# fails cleanly when invoked from a no-tty agent shell (where -w /dev/tty lies).
notify_user() {
  local rule="$1" msg="$2"
  mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null || true
  printf '%s [secret-leak guard] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$rule" "$msg" >> "$GUARD_LOG" 2>/dev/null || true
  if (: > /dev/tty) 2>/dev/null; then
    {
      printf '\n\033[1;31m== secret-leak guard BLOCKED ==\033[0m\n'
      printf '  rule: %s\n' "$rule"
      printf '  why:  %s\n' "$msg"
      printf '  bypass: append `# allow-secret-print` to the command (end-of-line)\n'
      printf '  log:  %s\n\n' "$GUARD_LOG"
    } > /dev/tty 2>/dev/null || true
  fi
}

# End-of-line sentinel check. grep is line-oriented; the sentinel must occur at
# the end of at least one line of the command. This prevents a literal sentinel
# inside a quoted string ("see # allow-secret-print docs") from bypassing.
if ! echo "$COMMAND" | grep -qE '# allow-secret-print[[:space:]]*$'; then

  # Rule 1: ${SECRET_VAR:-non-empty-fallback}
  # The :- form substitutes VAR's VALUE when set. With a non-empty fallback this
  # is almost always a leak: output is either the secret or the fallback string.
  # ${VAR:-} (empty fallback) is allowed because it's the canonical safe-check form.
  if echo "$COMMAND" | grep -qiE "\\\$\\{${SECRET_NAME}:-[^}]"; then
    notify_user "R1-default-expansion" "\${VAR:-fallback} on secret-named env var"
    cat >&2 <<'EOF'
BLOCKED: ${VAR:-fallback} parameter expansion on a secret-named env var.
The :- form returns VAR's VALUE when set, leaking the secret to stdout/context.

Safe alternatives:
  [ -n "${VAR:-}" ] && echo set || echo unset
  printf '%s\n' "${VAR:+set}"
  python3 -c "import os; print('set' if os.environ.get('VAR') else 'unset')"

If intentional, append `# allow-secret-print` at end-of-line.
EOF
    exit 2
  fi

  # Rule 2: echo/printf of a secret-named env var.
  # Matches dangerous expansion forms but allows ${VAR:+word} (which substitutes
  # the word, never the value). Dangerous: $VAR (bare), ${VAR} (bare braces).
  # The trailing boundary `[^a-zA-Z0-9_]|$` ensures the secret keyword is at the
  # END of the identifier (so KEYBOARD/TOKENS_PROCESSED don't false-positive).
  if echo "$COMMAND" | grep -qiE "(^|[^a-zA-Z0-9_/])(echo|printf)\s+[^|;]*\\\$(\\{${SECRET_NAME}\\}|${SECRET_NAME}([^a-zA-Z0-9_]|\$))"; then
    notify_user "R2-echo-printf" "echo/printf of \$SECRET_VAR or \${SECRET_VAR}"
    cat >&2 <<'EOF'
BLOCKED: echo/printf of a secret-named env var would emit its value to stdout
and into conversation context. Use a safe check that prints "set"/"unset" only:
  [ -n "${VAR:-}" ] && echo set || echo unset
  printf '%s\n' "${VAR:+set}"

If intentional, append `# allow-secret-print` at end-of-line.
EOF
    exit 2
  fi

  # Rule 3: printenv on a secret-named env var
  if echo "$COMMAND" | grep -qiE "(^|[^a-zA-Z0-9_/])printenv\s+${SECRET_NAME}([^a-zA-Z0-9_]|\$)"; then
    notify_user "R3-printenv" "printenv SECRET_VAR"
    echo "BLOCKED: printenv on a secret-named env var dumps its value. Use [ -n \"\${VAR:-}\" ] && echo set." >&2
    exit 2
  fi

  # Rule 4: env piped to grep with a secret-name pattern (dumps env then filters)
  if echo "$COMMAND" | grep -qiE "(^|[^a-zA-Z0-9_/])env\b[^|]*\|\s*grep[^|]*${SECRET_NAME}([^a-zA-Z0-9_]|\$)"; then
    notify_user "R4-env-grep" "env | grep SECRET_NAME"
    echo "BLOCKED: 'env | grep SECRETNAME' prints the full VAR=VALUE line. Use [ -n \"\${VAR:-}\" ] && echo set instead." >&2
    exit 2
  fi

fi

exit 0
