#!/usr/bin/env bash
# file-lock-gate.sh — PreToolUse hook for Edit/Write
#
# Checks if the target file is in the shared-files list and if so,
# verifies the current session holds the file-lock. Blocks the edit
# if the lock is held by another session.
#
# Input: JSON on stdin with tool_input.file_path
# Output: JSON verdict — proceed, warn, or block

set -euo pipefail

# Only gate if we're in a mesh worktree (not the anchor's main repo)
CWD=$(pwd)
if [[ "$CWD" != *"/reverie-wt-"* ]]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Read tool input
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Normalize: extract the crate-relative path
REL_PATH="${FILE_PATH#/home/*/projects/reverie*/}"
REL_PATH="${FILE_PATH##*/reverie-wt-*/}"

# Shared files that require locks
SHARED_FILES=(
    "crates/reverie-store/src/backends/engram_compat.rs"
    "crates/reverie-store/src/engram_types.rs"
    "crates/reverie-store/src/lib.rs"
    "crates/reverie-store/src/scoring.rs"
    "crates/reverie-store/src/backends/sqlite_vec.rs"
    "crates/reverie-domain/src/lib.rs"
    "crates/reverie-domain/src/traits.rs"
    "crates/reverie-domain/src/observation.rs"
    "crates/reverie-bench/src/main.rs"
    "crates/reveried/src/main.rs"
    "Cargo.toml"
)

# Check if this file matches any shared file
MATCHED=""
for sf in "${SHARED_FILES[@]}"; do
    if [[ "$REL_PATH" == *"$sf"* ]] || [[ "$FILE_PATH" == *"$sf"* ]]; then
        MATCHED="$sf"
        break
    fi
done

if [ -z "$MATCHED" ]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Check if we hold the lock
AREA="file::${MATCHED//\//__}"
AREA="${AREA#file::crates/}"  # normalize like file-lock does
LOCK_DIR="/tmp/claude-coord/locks/project:reverie:${AREA}"

if [ ! -d "$LOCK_DIR" ]; then
    # No lock held — warn but allow (worker should acquire first)
    echo "{\"decision\": \"approve\", \"message\": \"WARNING: editing shared file '$MATCHED' without file-lock. Run: file-lock acquire reverie $MATCHED\"}"
    exit 0
fi

# Lock exists — check if WE hold it
MY_SESSION=""
if [ -f /tmp/claude-coord/sessions/claude-pid-$$.json ]; then
    MY_SESSION="claude-pid-$$"
else
    # Find our session by scanning
    for sf in /tmp/claude-coord/sessions/claude-pid-*.json; do
        pid=$(jq -r '.claude_pid' "$sf" 2>/dev/null)
        if [ "$pid" = "$$" ] || [ "$pid" = "$PPID" ]; then
            MY_SESSION=$(basename "$sf" .json)
            break
        fi
    done
fi

OWNER=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo "unknown")

if [ "$OWNER" = "$MY_SESSION" ]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Someone else holds the lock — block
echo "{\"decision\": \"block\", \"reason\": \"File '$MATCHED' is locked by $OWNER. Wait for release or work on something else. Check: file-lock list reverie\"}"
exit 0
