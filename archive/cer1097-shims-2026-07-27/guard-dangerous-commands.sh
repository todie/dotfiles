#!/usr/bin/env bash
# guard-dangerous-commands.sh — thin shim to reverie-guard (CER-1097 cutover)
#
# When REVERIE_GUARD_ENFORCE=1 and the reverie-guard binary is on PATH, this
# hook execs the binary, which handles dangerous-command detection in Rust.
# The binary's stdout (permissionDecision JSON) is the hook contract.
#
# When the binary is absent or enforce is off, this hook falls back to the
# legacy shell rules below — preserving the live guard during rollout.
#
# Dead regex blocks from the pre-cutover version are deleted; the binary
# carries the dangerous-command patterns (rm -rf /, force-push main,
# curl|bash) and the legacy fallback carries the patterns the binary doesn't
# yet cover (destructive DB, critical dotfiles, secret-leak prevention).
set -euo pipefail

GUARD_BIN="${REVERIE_GUARD_BIN:-reverie-guard}"

# --- Cutover: exec reverie-guard when enforce is on + binary exists ---------
if [ "${REVERIE_GUARD_ENFORCE:-0}" = "1" ] || [ "${REVERIE_GUARD_MODE:-}" = "enforce" ]; then
  if command -v "$GUARD_BIN" >/dev/null 2>&1; then
    # Exec the binary — it reads stdin, emits permissionDecision JSON, exits.
    exec "$GUARD_BIN" --enforce
  fi
  # Binary absent + enforce mode = fail-closed (deny everything from Bash).
  echo '{"permissionDecision":"deny","reason":"reverie-guard binary not found in enforce mode"}' >&2
  exit 2
fi

# --- Shadow mode: run the binary in shadow for logging, then fall through ----
if command -v "$GUARD_BIN" >/dev/null 2>&1; then
  # Run in shadow mode — logs WOULD_DENY but returns allow (exit 0).
  "$GUARD_BIN" --shadow </dev/null 2>/dev/null || true
fi

# --- Legacy fallback (shadow mode or binary absent) -------------------------
# Only the patterns reverie-guard does NOT yet cover remain here.
# The binary handles: rm -rf /, force-push main, curl|bash.
# This fallback handles: destructive DB, critical dotfile writes,
# unqualified DELETE, secret-leak prevention.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

PROT_DOT='(~|\$\{?HOME\}?|/home/ctodie)/\.(ssh|gpg|secrets|gitconfig)'
LOCAL_HOST='https?://([^/@[:space:]]*@)?(127\.0\.0\.1|0\.0\.0\.0|localhost|host\.docker\.internal|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)(:[0-9]+)?([/[:space:]]|$)'

scan_segment() {
  local seg="$1"

  # Destructive DB (DROP/TRUNCATE always; unqualified DELETE FROM = mass delete)
  if echo "$seg" | grep -qiE '(DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)|TRUNCATE\s+(TABLE\s+)?\S+)'; then
    echo "BLOCKED: Destructive database operation (DROP/TRUNCATE) detected." >&2; exit 2
  fi
  if echo "$seg" | grep -qiE 'DELETE\s+FROM\s+\S+' && ! echo "$seg" | grep -qiE 'DELETE\s+FROM\s+.*[^a-zA-Z_]WHERE[^a-zA-Z_]'; then
    echo "BLOCKED: Unqualified DELETE FROM (no WHERE) is a mass delete." >&2; exit 2
  fi

  # Critical dotfile writes (redirect/tee/sed-i adjacent; cp/mv/install/rsync/sed-i dest = last token).
  if echo "$seg" | grep -qE "(>>?|tee([[:space:]]+-a)?|sed[[:space:]]+-i[^[:space:]]*)[[:space:]]*[\"']?${PROT_DOT}"; then
    echo "BLOCKED: Cannot write to critical dotfiles (.ssh, .gpg, .secrets, .gitconfig)." >&2; exit 2
  fi
  case "$seg" in
    *"cp "*|*"mv "*|*"install "*|*"rsync "*|*"sed -i"*|*"sed --in-place"*)
      _dst=$(printf '%s' "$seg" | awk '{print $NF}' | sed -E "s/^[\"']//; s/[\"']\$//")
      if printf '%s' "$_dst" | grep -qE "^${PROT_DOT}"; then
        echo "BLOCKED: Cannot write to critical dotfiles as a copy/move destination." >&2; exit 2
      fi ;;
  esac

  # Remote script piped to an interpreter — localhost carve-out scoped to THIS statement.
  if echo "$seg" | grep -qE '(curl|wget)\s.*\|\s*(bash|sh|zsh|python[0-9.]*|perl|ruby|node)' \
     && ! echo "$seg" | grep -qE "$LOCAL_HOST"; then
    echo "BLOCKED: Piping remote content to interpreter. Download first, review, then run." >&2; exit 2
  fi
}

while IFS= read -r _seg; do
  [ -n "$_seg" ] && scan_segment "$_seg"
done < <(printf '%s\n' "$COMMAND" | sed -E 's/&&/\n/g; s/[|][|]/\n/g; s/;/\n/g')

# --- Secret-leak prevention (same as pre-cutover) ----------------------------
SECRET_NAME='([A-Za-z_][A-Za-z0-9_]*)?(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CRED|PRIVATE|APIKEY)'
GUARD_LOG="$HOME/.claude/logs/secret-guard.log"

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

if ! echo "$COMMAND" | grep -qE '# allow-secret-print[[:space:]]*$'; then
  # Rule 1: ${SECRET_VAR:-non-empty-fallback}
  if echo "$COMMAND" | grep -qE "\$\{?[A-Za-z_][A-Za-z0-9_]*${SECRET_NAME#(}?}?:-[^}]+\}"; then
    notify_user "secret-env-substitution" "$COMMAND"
    exit 2
  fi
  # Rule 2: echo/printf of a secret-named variable
  if echo "$COMMAND" | grep -qiE "(echo|printf).*(\\\$|\\$\{)[A-Za-z_][A-Za-z0-9_]*${SECRET_NAME#(}?}"; then
    notify_user "secret-echo" "$COMMAND"
    exit 2
  fi
  # Rule 3: cat of a secret-named file path
  if echo "$COMMAND" | grep -qiE "cat\s+.*(/etc/(shadow|passwd)|${PROT_DOT}|.*\.env|.*\.pem|.*\.key)"; then
    notify_user "secret-file-read" "$COMMAND"
    exit 2
  fi
fi

exit 0
