#!/usr/bin/env bash
# agent-auto-register.sh — Claude Code PreToolUse hook for the `Agent` tool.
#
# Auto-registers every Claude-Code subagent dispatch with reveried's
# /agents registry (TOD-602) so the Agent-tool path does not bypass
# observability the way mesh-spawn (TOD-573) does not.
#
# Input:  PreToolUse JSON on stdin — {tool_name, tool_input:{description,
#         subagent_type, prompt}}.
# Output: Always `{"decision":"approve"}` on stdout — registration is
#         observability, never a gate.
# Exit:   Always 0.
#
# Canonical source lives at scripts/agent-auto-register.sh in the reverie
# repo; the live hook is installed at ~/.claude/hooks/agent-auto-register.sh
# and wired via the Agent matcher in ~/.claude/settings.json.
#
# Env overrides (primarily for tests):
#   REVERIE_AGENT_REGISTER_URL  Full register endpoint URL.
#                               Default: http://127.0.0.1:7437/agents/register
#   REVERIE_AGENT_REGISTER_LOG  Path to append JSONL registration log.
#                               Default: /tmp/agent-registrations.log
#   REVERIE_AGENT_REGISTER_TIMEOUT  curl --max-time (default 2).
#   REVERIE_AGENT_COORD_BIN     coord CLI path (default: coord on PATH).
#                               Set to empty string to disable the coord
#                               dual-write entirely (tests, air-gap).
#   REVERIE_AGENT_COORD_TIMEOUT timeout(1) for coord register (default 2s).
#
# Dual-write (TOD-TBD): after the best-effort POST to /agents/register we
# ALSO invoke `coord register` so the subagent shows up in the coord
# filesystem registry (/tmp/claude-coord/sessions/) that `coord peers` and
# `cortex peers` read. Without this, Agent-tool dispatches populate only
# the reveried HTTP /agents registry and are invisible to the mesh dash.
# The coord call is best-effort, wrapped in timeout(1), and never blocks
# the approve verdict. PreToolUse cannot run on Agent completion, so
# coord records leak until their TTL expires — same trade-off as every
# short-lived CLI-registered peer. Follow-up for proper Drop semantics
# tracked in the PR body.

set -u
# Intentionally NOT -e: every failure path must still emit the approve
# verdict. We trap the happy-path logic in a subshell and approve
# regardless.

approve() { printf '{"decision":"approve"}\n'; exit 0; }

ENDPOINT="${REVERIE_AGENT_REGISTER_URL:-http://127.0.0.1:7437/agents/register}"
LOG_PATH="${REVERIE_AGENT_REGISTER_LOG:-/tmp/agent-registrations.log}"
TIMEOUT="${REVERIE_AGENT_REGISTER_TIMEOUT:-2}"

INPUT=$(cat || true)

# Tooling guard: without jq we can't safely extract the payload; approve
# and bail rather than blocking the dispatch.
if ! command -v jq >/dev/null 2>&1; then
    approve
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
# Defensive: this hook is wired on matcher=Agent, but if it ever runs for
# another tool, approve without touching the registry.
if [ "$TOOL_NAME" != "Agent" ]; then
    approve
fi

DESCRIPTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null || true)
SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.tool_input.prompt // ""' 2>/dev/null || true)

# ─── Role mapping ───────────────────────────────────────────────────────
# subagent_type → coord role (see KNOWN_ROLES in agents_register.rs).
# Anything unrecognized lands on "builder" (the default dispatch lane).
map_role() {
    case "$1" in
        code-reviewer|reviewer)           echo "reviewer" ;;
        researcher|research|explore)      echo "researcher" ;;
        archivist|archive)                echo "archivist" ;;
        monitor|sentinel)                 echo "$1" ;;
        hypervisor|anchor|wizard)         echo "$1" ;;
        release|control-room)             echo "$1" ;;
        general-purpose|builder|"")       echo "builder" ;;
        *)                                echo "builder" ;;
    esac
}
ROLE=$(map_role "$SUBAGENT_TYPE")

# ─── Capability inference ───────────────────────────────────────────────
# Derive from description+prompt keywords; default to a conservative
# read,write,bash triad. Must match [a-zA-Z0-9_.-].
derive_caps() {
    local text caps
    text=$(printf '%s\n%s' "$DESCRIPTION" "$PROMPT" | tr '[:upper:]' '[:lower:]')
    caps=""
    case "$text" in
        *" read"*|*"grep"*|*"search"*|*"find "*) caps="read" ;;
    esac
    case "$text" in
        *"write"*|*"edit"*|*"commit"*|*"pr "*|*"pull request"*)
            caps="${caps:+$caps,}write" ;;
    esac
    case "$text" in
        *"bash"*|*"shell"*|*"run "*|*"cargo"*|*"npm"*|*"test "*)
            caps="${caps:+$caps,}bash" ;;
    esac
    if [ -z "$caps" ]; then
        caps="read,write,bash"
    fi
    echo "$caps"
}
CAPABILITIES=$(derive_caps)

# ─── Identity ───────────────────────────────────────────────────────────
PPID_VAL=${PPID:-0}
NOW_EPOCH=$(date +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SESSION_ID="claude-agent-${NOW_EPOCH}-${PPID_VAL}-$$"
# Deterministic, non-uuidv7 request_id — the registry only requires
# non-empty, and this hook is fire-and-forget so idempotency is moot.
REQUEST_ID="claude-agent-${NOW_EPOCH}-${PPID_VAL}-$$"
TMUX_SESSION="${TMUX_PANE:-claude-code}"
CWD_VAL="${PWD:-$HOME}"
WAKE_METHOD="tmux-send-keys"

# ─── Build payload and POST ─────────────────────────────────────────────
PAYLOAD=$(jq -nc \
    --arg request_id   "$REQUEST_ID" \
    --arg session_id   "$SESSION_ID" \
    --arg role         "$ROLE" \
    --arg tmux_session "$TMUX_SESSION" \
    --arg cwd          "$CWD_VAL" \
    --arg capabilities "$CAPABILITIES" \
    --arg wake_method  "$WAKE_METHOD" \
    --arg requested_at "$NOW_ISO" \
    '{request_id:$request_id,session_id:$session_id,role:$role,tmux_session:$tmux_session,cwd:$cwd,capabilities:$capabilities,wake_method:$wake_method,requested_at:$requested_at}' 2>/dev/null || echo '{}')

STATUS="unknown"
BODY=""
if command -v curl >/dev/null 2>&1; then
    # Best-effort POST. Swallow network failures; they're expected when
    # reveried is down. We still log the attempt.
    HTTP_RESP=$(curl -sS -o /tmp/agent-auto-register.body.$$ \
        -w '%{http_code}' \
        --max-time "$TIMEOUT" \
        -H 'content-type: application/json' \
        -X POST \
        --data "$PAYLOAD" \
        "$ENDPOINT" 2>/dev/null)
    # curl writes http_code to stdout even on connection failure (as
    # "000"). On timeout / non-zero exit with no -w output, fall back.
    STATUS="${HTTP_RESP:-000}"
    if [ -f /tmp/agent-auto-register.body.$$ ]; then
        BODY=$(head -c 4096 /tmp/agent-auto-register.body.$$ 2>/dev/null || true)
        rm -f /tmp/agent-auto-register.body.$$ 2>/dev/null || true
    fi
fi

# ─── Dual-write: coord filesystem registry (TOD-TBD) ────────────────────
# Mirror the registration into coord so `coord peers` and `cortex peers`
# can see Agent-tool subagents. Best-effort: a missing/failing coord must
# NEVER block the approve verdict. The reveried HTTP registry above is
# the source of truth; coord is the view layer.
COORD_BIN="${REVERIE_AGENT_COORD_BIN-coord}"
COORD_TIMEOUT="${REVERIE_AGENT_COORD_TIMEOUT:-2}"
COORD_STATUS="skipped"
COORD_BODY=""
if [ -n "$COORD_BIN" ] && command -v "$COORD_BIN" >/dev/null 2>&1; then
    COORD_BLOB=$(jq -nc \
        --arg caps "$CAPABILITIES" \
        --arg cwd  "$CWD_VAL" \
        --arg tmux "$TMUX_SESSION" \
        --arg sub  "$SUBAGENT_TYPE" \
        '{capabilities:($caps|split(",")),cwd:$cwd,tmux:$tmux,subagent_type:$sub,auto_registered:true}' 2>/dev/null || echo '{}')
    COORD_TASK="claude-agent ${SUBAGENT_TYPE:-general-purpose}"
    # Wrap in timeout(1) if available; fall back to a bare call. Capture
    # exit code without tripping `set -u` on unset positional params.
    if command -v timeout >/dev/null 2>&1; then
        COORD_BODY=$(COORD_SESSION_ID="$SESSION_ID" timeout "$COORD_TIMEOUT" \
            "$COORD_BIN" register \
            --role "$ROLE" \
            --task "$COORD_TASK" \
            --blob "$COORD_BLOB" 2>&1)
        COORD_RC=$?
    else
        COORD_BODY=$(COORD_SESSION_ID="$SESSION_ID" \
            "$COORD_BIN" register \
            --role "$ROLE" \
            --task "$COORD_TASK" \
            --blob "$COORD_BLOB" 2>&1)
        COORD_RC=$?
    fi
    if [ "$COORD_RC" -eq 0 ]; then
        COORD_STATUS="ok"
    else
        COORD_STATUS="error:$COORD_RC"
    fi
    # Trim to keep log lines bounded.
    COORD_BODY=$(printf '%s' "$COORD_BODY" | head -c 1024 || true)
fi

# ─── Log (JSONL) ────────────────────────────────────────────────────────
LOG_DIR=$(dirname "$LOG_PATH")
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || true
fi
LOG_LINE=$(jq -nc \
    --arg ts           "$NOW_ISO" \
    --arg endpoint     "$ENDPOINT" \
    --arg http_status  "$STATUS" \
    --arg role         "$ROLE" \
    --arg subagent     "$SUBAGENT_TYPE" \
    --arg session_id   "$SESSION_ID" \
    --arg request_id   "$REQUEST_ID" \
    --arg capabilities "$CAPABILITIES" \
    --arg body         "$BODY" \
    --arg coord_status "$COORD_STATUS" \
    --arg coord_body   "$COORD_BODY" \
    '{ts:$ts,endpoint:$endpoint,http_status:$http_status,role:$role,subagent:$subagent,session_id:$session_id,request_id:$request_id,capabilities:$capabilities,body:$body,coord_status:$coord_status,coord_body:$coord_body}' 2>/dev/null || true)
if [ -n "$LOG_LINE" ]; then
    printf '%s\n' "$LOG_LINE" >>"$LOG_PATH" 2>/dev/null || true
fi

approve
