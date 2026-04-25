#!/usr/bin/env bash
# Blocks destructive shell commands in Claude Code sessions.
# Runs as a PreToolUse hook for Bash — receives tool input on stdin as JSON.

set -euo pipefail

input="$(cat)"
command="$(echo "$input" | jq -r '.command // ""')"

# Patterns that require explicit user confirmation before Claude runs them.
dangerous=(
  "rm -rf /"
  "rm -rf ~"
  "rm -rf \$HOME"
  "dd if="
  "mkfs"
  ":(){:|:&};:"
  "chmod -R 777 /"
  "chown -R"
  "> /dev/sda"
  "format"
  "shutdown"
  "reboot"
  "halt"
  "poweroff"
)

for pattern in "${dangerous[@]}"; do
  if echo "$command" | grep -qF "$pattern"; then
    echo "BLOCKED: dangerous command pattern detected: $pattern" >&2
    exit 1
  fi
done

exit 0
