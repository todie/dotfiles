#!/usr/bin/env bash
# guard-secret-access.sh — thin shim to reverie-guard (CER-1097 cutover)
#
# When reverie-guard implements secret-file-access rules (CER-1094), this hook
# will exec the binary. Until then, the full shell logic below runs — the
# binary does not yet cover secret-path detection for Bash/Read/Grep tools.
#
# The shim structure is in place: when REVERIE_GUARD_ENFORCE=1 and the binary
# gains secret-access rules, the exec path activates and the shell regex below
# becomes the fallback.
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

GUARD_LOG="$HOME/.claude/logs/secret-guard.log"
mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null || true

log_block() {
  local rule="$1" msg="$2"
  printf '%s [secret-access guard] %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$rule" "$msg" >> "$GUARD_LOG" 2>/dev/null || true
  if (: > /dev/tty) 2>/dev/null; then
    printf '\n\033[1;31m== secret-access guard BLOCKED ==\033[0m\n  rule: %s\n  why:  %s\n  log:  %s\n\n' "$rule" "$msg" "$GUARD_LOG" > /dev/tty 2>/dev/null || true
  fi
}

# ─── Known secret paths (deny list) ─────────────────────────────────────────
SECRET_PATHS_REGEX='(\.secrets(\.[A-Za-z0-9_-]+)?|\.aws/credentials|\.ssh/id_(rsa|ed25519|ecdsa|dsa)(\.[A-Za-z0-9_-]+)?|\.gnupg/(private-keys|pubring|secring)|\.docker/config\.json|\.config/gcloud/application_default_credentials\.json|\.config/gcloud/legacy_credentials|\.config/google-drive-mcp/[^[:space:]]*\.json|\.config/google-workspace-admin/[^[:space:]]*\.json|\.config/op(/[^[:space:]]*)?|service-account[^[:space:]]*\.json|[^[:space:]]*_credentials\.json|\.env(\.(local|production|staging|test))?|\.npmrc|\.pypirc|\.netrc|backend\.hcl)([[:space:]"'\''`;:|&<>(){}]|$)'

READ_CMDS='cat|less|more|head|tail|bat|nl|od|xxd|hexdump|strings|base64|gzip|xz|zstd|tar|cp|rsync|scp|curl|wget|grep|egrep|fgrep|rg|ag|awk|gawk|sed|jq|yq|python3?|node|ruby|perl|dd|vi|vim|view|nvim|emacs|nano|cut|sort|uniq|tee|fold|paste|column|comm|join|xargs|diff|tac|rev'

# ─── Tool: Bash ─────────────────────────────────────────────────────────────
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0

  # Bypass sentinel (end-of-line)
  if echo "$COMMAND" | grep -qE '# allow-secret-read[[:space:]]*$'; then
    exit 0
  fi

  # S1: read command + secret path in the same segment
  while IFS= read -r _seg; do
    if echo "$_seg" | grep -qE "(^|[^a-zA-Z])($READ_CMDS)([[:space:]]|$)" \
       && echo "$_seg" | grep -qE "$SECRET_PATHS_REGEX"; then
      log_block "secret-path-read" "$_seg"
      exit 2
    fi
  done < <(printf '%s\n' "$COMMAND" | sed -E 's/&&/\n/g; s/[|][|]/\n/g; s/;/\n/g')

  # S2: redirect from a secret path (< secret or $(<secret))
  if echo "$COMMAND" | grep -qE "(<|\$\()<.*$SECRET_PATHS_REGEX"; then
    log_block "secret-redirect-read" "$COMMAND"
    exit 2
  fi
fi

# ─── Tool: Read ─────────────────────────────────────────────────────────────
if [ "$TOOL" = "Read" ]; then
  FP=$(echo "$INPUT" | jq -r '.file_path // empty')
  if [ -n "$FP" ] && echo "$FP" | grep -qE "$SECRET_PATHS_REGEX"; then
    log_block "read-tool-secret-path" "$FP"
    exit 2
  fi
fi

# ─── Tool: Grep ─────────────────────────────────────────────────────────────
if [ "$TOOL" = "Grep" ]; then
  PATTERN=$(echo "$INPUT" | jq -r '.pattern // empty')
  PATH_ARG=$(echo "$INPUT" | jq -r '.path // empty')
  if [ -n "$PATH_ARG" ] && echo "$PATH_ARG" | grep -qE "$SECRET_PATHS_REGEX"; then
    log_block "grep-secret-path" "$PATH_ARG"
    exit 2
  fi
fi

exit 0
