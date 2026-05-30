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

# Block destructive database operations.
#   - DROP/TRUNCATE are always destructive → block outright.
#   - DELETE FROM <table> with NO WHERE clause is a mass delete → block; a
#     WHERE-qualified DELETE is a normal targeted op and is allowed. (The old
#     rule required a trailing `;`, so `psql -c "DELETE FROM users"` slipped.)
if echo "$COMMAND" | grep -qiE '(DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)|TRUNCATE\s+(TABLE\s+)?\S+)'; then
  echo "BLOCKED: Destructive database operation (DROP/TRUNCATE) detected. Use explicit confirmation." >&2
  exit 2
fi
if echo "$COMMAND" | grep -qiE 'DELETE\s+FROM\s+\S+' && ! echo "$COMMAND" | grep -qiE 'DELETE\s+FROM\s+.*[^a-zA-Z_]WHERE[^a-zA-Z_]'; then
  echo "BLOCKED: Unqualified DELETE FROM (no WHERE) is a mass delete. Add a WHERE clause or confirm explicitly." >&2
  exit 2
fi

# Block force pushes to main/master, regardless of flag order or syntax.
# Old rules required the force flag BEFORE the branch, so `git push origin main
# --force` and `git push origin +main` (refspec force) both slipped through.
# Detect loosely (git + push + a force indicator) and confirm a protected ref
# is referenced. Force-push to a NON-protected feature branch stays allowed.
if echo "$COMMAND" | grep -qE '(^|[^[:alnum:]])git([[:space:]]|$)' \
   && echo "$COMMAND" | grep -qE '(^|[^[:alnum:]])push([^[:alnum:]]|$)' \
   && echo "$COMMAND" | grep -qE '(--force([^-[:alnum:]]|=|$)|--force-with-lease|(^|[[:space:]])-[a-zA-Z]*f([[:space:]]|$)|[[:space:]]\+(main|master|HEAD)([^[:alnum:]]|$))' \
   && echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_])(main|master)([^[:alnum:]_]|$)'; then
  echo "BLOCKED: Force push to main/master is not allowed." >&2
  exit 2
fi

# Block writing to critical dotfiles (.ssh/.gpg/.secrets/.gitconfig). Covers
# redirect/append/tee/sed-i (target adjacent to the operator) and cp/mv/install/
# rsync (protected path as the LAST token = destination), with ~ / $HOME /
# ${HOME} / absolute forms. Reads (cat/grep ~/.ssh/config) are NOT writers.
PROT_DOT='(~|\$\{?HOME\}?|/home/ctodie)/\.(ssh|gpg|secrets|gitconfig)'
if echo "$COMMAND" | grep -qE "(>>?|tee([[:space:]]+-a)?|sed[[:space:]]+-i[^[:space:]]*)[[:space:]]*[\"']?${PROT_DOT}"; then
  echo "BLOCKED: Cannot write to critical dotfiles (.ssh, .gpg, .secrets, .gitconfig) via redirect/tee/sed -i." >&2
  exit 2
fi
case "$COMMAND" in
  *"cp "*|*"mv "*|*"install "*|*"rsync "*|*"sed -i"*|*"sed --in-place"*)
    # destination / in-place target = last token of the first command segment
    _seg=$(printf '%s' "$COMMAND" | sed -E 's/[[:space:]]*[;|&].*$//')
    _dst=$(printf '%s' "$_seg" | awk '{print $NF}' | sed -E "s/^[\"']//; s/[\"']\$//")
    if printf '%s' "$_dst" | grep -qE "^${PROT_DOT}"; then
      echo "BLOCKED: Cannot write to critical dotfiles (.ssh, .gpg, .secrets, .gitconfig) as a copy/move/sed-i destination." >&2
      exit 2
    fi
    ;;
esac

# Block running scripts piped from the internet.
# Localhost / 127.0.0.1 / docker-internal / private 172.16-31 hosts are NOT
# remote — allow piping from those (the dev mesh hits them constantly: ollama,
# reveried, prometheus). The local-host token is anchored to the URL HOST (it
# must be followed by :port, /, whitespace or end) so an attacker hostname like
# `localhost.evil.com` no longer satisfies the carve-out.
LOCAL_HOST='https?://([^/@[:space:]]*@)?(127\.0\.0\.1|0\.0\.0\.0|localhost|host\.docker\.internal|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)(:[0-9]+)?([/[:space:]]|$)'
if echo "$COMMAND" | grep -qE '(curl|wget)\s.*\|\s*(bash|sh|zsh|python[0-9.]*|perl|ruby|node)' \
   && ! echo "$COMMAND" | grep -qE "$LOCAL_HOST"; then
  echo "BLOCKED: Piping remote content to interpreter. Download first, review, then run." >&2
  exit 2
fi

# Block recursive deletion of home or root, regardless of flag order/spelling.
# Old rule only matched `-rf`/`-r` immediately before the target at EOL, so
# `rm -fr ~`, `rm -r -f ~`, `rm -R ~`, `rm -rf --no-preserve-root /` slipped.
# Detect rm + a recursive flag + a target that IS home/root (subdirs allowed).
if echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_./-])rm([[:space:]]|$)' \
   && echo "$COMMAND" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)' \
   && echo "$COMMAND" | grep -qE '(^|[[:space:]])["'"'"']?(/|~|\$\{?HOME\}?|/home/ctodie|/root)/?["'"'"']?([[:space:]]|;|\||&|$)'; then
  echo "BLOCKED: Recursive deletion of home or root directory." >&2
  exit 2
fi

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
