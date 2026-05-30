#!/usr/bin/env bash
# guard-secret-access.sh — PreToolUse hook for Bash, Read, Grep
# Blocks tool invocations that would expose the contents of known secret files.
# Exit 0 = allow, Exit 2 = block.
#
# Origin: 2026-04-20 session where `grep content-mode` against ~/.secrets leaked
# full key values into the conversation transcript. PostToolUse cannot redact
# output post-hoc (the tool already ran), so we prevent the read at the source.
#
# Bypass: append `# allow-secret-read` to a Bash command at end-of-line.
#         For Read/Grep, there is no bypass — adjust the allowlist if needed.
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

GUARD_LOG="$HOME/.claude/logs/secret-guard.log"
mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null || true

log_block() {
  local rule="$1" detail="$2"
  printf '%s [secret-access guard] %s: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$rule" "$detail" >> "$GUARD_LOG" 2>/dev/null || true
  if (: > /dev/tty) 2>/dev/null; then
    {
      printf '\n\033[1;31m== secret-access guard BLOCKED ==\033[0m\n'
      printf '  rule: %s\n' "$rule"
      printf '  why:  %s\n' "$detail"
      printf '  log:  %s\n\n' "$GUARD_LOG"
    } > /dev/tty 2>/dev/null || true
  fi
}

# ─── Known secret paths (deny list) ─────────────────────────────────────────
# Matches both ~ and literal $HOME forms. Conservative — filename patterns
# rather than broad directory sweeps, to keep false positives low.
# Trailing boundary ([^A-Za-z0-9]|$) is REQUIRED: without it, `\.env` matched
# `.environ` inside `os.environ[...]` and similar, false-blocking ordinary grep
# commands. The boundary makes each pattern match a real path token, not a
# substring of a longer word.
SECRET_PATHS_REGEX='(\.secrets(\.[A-Za-z0-9_-]+)?|\.aws/credentials|\.ssh/id_(rsa|ed25519|ecdsa|dsa)(\.[A-Za-z0-9_-]+)?|\.gnupg/(private-keys|pubring|secring)|\.docker/config\.json|\.config/gcloud/application_default_credentials\.json|\.config/gcloud/legacy_credentials|\.config/google-drive-mcp/[^[:space:]]*\.json|\.config/google-workspace-admin/[^[:space:]]*\.json|\.config/op(/[^[:space:]]*)?|service-account[^[:space:]]*\.json|[^[:space:]]*_credentials\.json|\.env(\.(local|production|staging|test))?|\.npmrc|\.pypirc|\.netrc)([^A-Za-z0-9]|$)'

# Commands that emit file content — pairing one with a secret path is suspect.
# Includes editors and line tools that were previously missing (strings/vi/cut/
# sort/uniq/tee/xargs/…); native-bash reads (`< secret`, `$(<secret)`) are
# caught separately by the redirect check in S1.
READ_CMDS='cat|less|more|head|tail|bat|nl|od|xxd|hexdump|strings|base64|gzip|xz|zstd|tar|cp|rsync|scp|curl|wget|grep|egrep|fgrep|rg|ag|awk|gawk|sed|jq|yq|python3?|node|ruby|perl|dd|vi|vim|view|nvim|emacs|nano|cut|sort|uniq|tee|fold|paste|column|comm|join|xargs|diff|tac|rev'

# ─── Tool: Bash ─────────────────────────────────────────────────────────────
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0

  if echo "$COMMAND" | grep -qE '# allow-secret-read[[:space:]]*$'; then
    exit 0
  fi

  # Rule S1: a secret path is EXPOSED — either via a content-reading command,
  # or via a native-bash read: an input redirect `< secret`, a `$(<secret)`
  # substitution, or mapfile/readarray/read fed from one. (The redirect forms
  # carry no reader verb, so they bypassed the verb-only check.)
  # Strip safe references (*.pub / *.example / *.sample / *.template) first.
  CMD_STRIPPED=$(echo "$COMMAND" | sed -E 's/[^[:space:]]+\.(pub|example|sample|template)([[:space:]]|$)/ /g')
  if echo "$CMD_STRIPPED" | grep -qE "$SECRET_PATHS_REGEX" \
     && { echo "$COMMAND" | grep -qE "(^|[^a-zA-Z0-9_/-])(${READ_CMDS})([[:space:]]|\$)" \
          || echo "$CMD_STRIPPED" | grep -qE "<[[:space:]]*[\"']?[^[:space:]\"'<>;|&]*${SECRET_PATHS_REGEX}" \
          || echo "$CMD_STRIPPED" | grep -qE "(^|[^a-zA-Z0-9_/-])(mapfile|readarray|read)([[:space:]]|\$)"; }; then
    log_block "S1-secret-path-reader" "command references a known secret path with a content-reading tool"
    cat >&2 <<'EOF'
BLOCKED: command would read a known secret file (~/.secrets, SSH private key,
service-account JSON, .env, credentials, gpg ring, etc.) with a tool that emits
its contents. The value would land in the conversation transcript.

Safe alternatives:
  [ -f <path> ] && echo exists             # presence check
  stat -c '%s %y' <path>                   # metadata only
  wc -l <path>                             # line count only
  awk -F= '/^[a-z_]+\s*=/{k=$1; if (k ~ /key|secret|pass/) print k" = <redacted>"; else print}' <path>

If intentional (e.g. scripted migration), append `# allow-secret-read` at
end-of-line. Prefer a per-call secret resolver (`op run`, `pass show | proc`)
so the value never enters a shell that Claude can see.
EOF
    exit 2
  fi

  # Rule S2: `env` without a filter that excludes secret names
  if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_/.~-])env([[:space:]]+(-0|--null|-u|-i))*([[:space:]]*\||[[:space:]]*$|[[:space:]]*>)' \
     && ! echo "$COMMAND" | grep -qiE 'grep\s+-v.*(KEY|TOKEN|SECRET|PASSWORD|CRED)'; then
    log_block "S2-env-dump" "bare \`env\` would list every var including secrets"
    cat >&2 <<'EOF'
BLOCKED: `env` without a filter dumps every environment variable, including
secrets. Use a name-filtered check:
  [ -n "${VAR:-}" ] && echo set
  env | grep -vE '(KEY|TOKEN|SECRET|PASSWORD|CRED)' | head

If intentional, append `# allow-secret-read` at end-of-line.
EOF
    exit 2
  fi

  exit 0
fi

# ─── Tool: Read ─────────────────────────────────────────────────────────────
if [ "$TOOL" = "Read" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$FILE_PATH" ] && exit 0

  # Safe: SSH/GPG pubkeys, template files
  case "$FILE_PATH" in
    *.pub|*.example|*.sample|*.template) exit 0 ;;
  esac

  if echo "$FILE_PATH" | grep -qE "$SECRET_PATHS_REGEX"; then
    log_block "S3-read-secret-file" "Read tool targeting secret file: $FILE_PATH"
    cat >&2 <<EOF
BLOCKED: Read tool targeting a known secret file:
  $FILE_PATH

Secret files are not permitted via the Read tool — the full contents would
land in conversation context. If you need to inspect structure, use Bash with
a projection that redacts values (see guard-secret-access.sh S1 alternatives).
EOF
    exit 2
  fi
  exit 0
fi

# ─── Tool: Grep ─────────────────────────────────────────────────────────────
if [ "$TOOL" = "Grep" ]; then
  G_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
  G_MODE=$(echo "$INPUT" | jq -r '.tool_input.output_mode // "files_with_matches"' 2>/dev/null)
  # An empty path means Grep searches the session cwd. If that cwd is itself a
  # secret dir (~/.config/op, ~/.aws, …), a content grep there would leak
  # values — so resolve to .cwd and apply the same check instead of bailing.
  [ -z "$G_PATH" ] && G_PATH=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$G_PATH" ] && exit 0

  if echo "$G_PATH" | grep -qE "$SECRET_PATHS_REGEX" && [ "$G_MODE" = "content" ]; then
    log_block "S4-grep-content-on-secret" "Grep content mode on secret path: $G_PATH"
    cat >&2 <<EOF
BLOCKED: Grep in \`content\` mode against a known secret path:
  $G_PATH

Content mode emits matching lines, which for secret files means the key values.
Use output_mode="files_with_matches" or "count" to check presence without
exposing values. For structure inspection, use Bash with a redacting awk
projection.
EOF
    exit 2
  fi
  exit 0
fi

exit 0
