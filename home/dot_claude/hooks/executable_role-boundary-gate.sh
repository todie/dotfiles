#!/usr/bin/env bash
# role-boundary-gate.sh — PreToolUse hook for Edit/Write
#
# Enforces role-scoped file path restrictions for mesh workers.
# Only active when REVERIE_MESH_ROLE is set (mesh worker context).

set -euo pipefail
source "${BASH_SOURCE[0]%/*}/lib.sh"
hook_name "role-boundary"

ROLE="${REVERIE_MESH_ROLE:-}"
[ -z "$ROLE" ] && exit 0  # Not a mesh worker — pass through

# Anchor and builder can write anywhere
case "$ROLE" in
  anchor|builder) exit 0 ;;
esac

# Read the tool input from stdin. NB: current Claude Code sends .tool_name and
# .tool_input.* — the old .tool / .input.file_path fields resolved empty, so
# this gate matched nothing and silently enforced no restriction at all.
INPUT=$(safe_read_stdin)
TOOL=$(json_field "$INPUT" '.tool_name')

# Only gate file-mutating tools
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(json_field "$INPUT" '.tool_input.file_path')
[ -z "$FILE_PATH" ] && FILE_PATH=$(json_field "$INPUT" '.tool_input.notebook_path')
[ -z "$FILE_PATH" ] && exit 0

# Canonicalize lexically (realpath -m needs no existence) BEFORE matching, so a
# path like docs/../../.ssh/authorized_keys can't satisfy a `docs/*` allow-rule
# and then resolve outside the root at write time.
FILE_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
REL_PATH=$(rel_path "$FILE_PATH")

# Reject anything that escapes the project root (absolute-outside or .. segment).
case "$REL_PATH" in
  /*|../*|*/../*|*/..) hook_deny "role-boundary: path escapes project root — $FILE_PATH" ;;
esac

# Role-specific path restrictions
case "$ROLE" in
  memory)
    case "$REL_PATH" in
      docs/*|CHANGELOG.md) ;; # allowed
      *) hook_deny "memory role: writes restricted to docs/ — delegate code changes to builder" ;;
    esac
    ;;
  research)
    case "$REL_PATH" in
      docs/research/*) ;; # allowed
      *) hook_deny "research role: writes restricted to docs/research/ — delegate other changes to anchor" ;;
    esac
    ;;
  security)
    case "$REL_PATH" in
      docs/security/*|Cargo.lock) ;; # allowed
      *) hook_deny "security role: writes restricted to docs/security/ and Cargo.lock — delegate code changes to builder" ;;
    esac
    ;;
  release)
    case "$REL_PATH" in
      CHANGELOG.md|Cargo.toml|crates/*/Cargo.toml|VERSION) ;; # allowed
      *) hook_deny "release role: writes restricted to CHANGELOG.md and version files — delegate code changes to builder" ;;
    esac
    ;;
esac

# Default: approve
exit 0
