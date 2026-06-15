#!/usr/bin/env bash
# guard-engram-protect.sh — PreToolUse hook protecting the engram memory store.
#
# ~/.engram (and ~/.local/share/engram) is reverie's irreplaceable, multi-GB
# memory DB. This blocks destructive / mutating tool ops against it:
#   - Bash: rm/rmdir/mv/dd/truncate/shred/unlink/mkfs/chmod/chown/chgrp/ln,
#           find -delete, sqlite write keywords (DROP/DELETE/UPDATE/INSERT/
#           REPLACE/VACUUM/ALTER/CREATE), and `>`/`>>` redirects targeting it.
#   - Write/Edit/MultiEdit/NotebookEdit: any file_path under the store.
# READS (cat/ls/du/head/tail/grep, sqlite SELECT, cp FROM it) are allowed.
#
# Deliberate, justified write? append  # allow-engram-write  to the Bash command
# AND say why in your reply. (The running reveried daemon writes the DB directly,
# not via tools, so it is unaffected by this hook.)
#
# Exit 0 = allow, Exit 2 = block.
set -euo pipefail

INPUT=$(cat 2>/dev/null || echo '{}')
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# Protected store: the .engram data dir or ~/.local/share/engram, at a real boundary.
PROT='(~|\$\{?HOME\}?|/home/ctodie)/(\.engram|\.local/share/engram)($|[^[:alnum:]_-])'

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || echo "")
    if printf '%s' "$FP" | grep -qE "$PROT"; then
      echo "BLOCKED (guard-engram-protect): $TOOL targets the protected engram store: $FP" >&2
      echo "~/.engram is reverie's irreplaceable memory DB and is not writable via tools." >&2
      exit 2
    fi
    exit 0
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
    [ -z "$CMD" ] && exit 0
    # Surfaced, deliberate override.
    if printf '%s' "$CMD" | grep -qF '# allow-engram-write'; then exit 0; fi
    # Only gate commands that reference the protected store.
    if ! printf '%s' "$CMD" | grep -qE "$PROT"; then exit 0; fi
    # Mutating verbs targeting it.
    DESTRUCTIVE='(^|[^[:alnum:]_/.-])(rm|rmdir|mv|dd|truncate|shred|unlink|mkfs[.a-z]*|chmod|chown|chgrp)([[:space:]]|$)|(^|[[:space:]])--?delete([[:space:]]|=|$)|(^|[^[:alnum:]_])ln[[:space:]].*-s|sqlite3?[^|]*\b(DROP|DELETE|UPDATE|INSERT|REPLACE|VACUUM|ALTER|CREATE)\b'
    # `>`/`>>` redirect whose target is the store.
    REDIR='>[>]?[[:space:]]*"?'"'"'?(~|\$\{?HOME\}?|/home/ctodie)/(\.engram|\.local/share/engram)'
    if printf '%s' "$CMD" | grep -qiE "$DESTRUCTIVE" || printf '%s' "$CMD" | grep -qE "$REDIR"; then
      echo "BLOCKED (guard-engram-protect): command would modify/delete the protected engram store (~/.engram)." >&2
      echo "It is reverie's irreplaceable memory DB (multi-GB). Reads are fine." >&2
      echo "Deliberate, justified write? append  # allow-engram-write  to the command and state why." >&2
      exit 2
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
