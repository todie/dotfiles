---
name: worker-supervisor-smoke
description: End-to-end smoke test of the mesh-spawn supervisor loop — kill a worker's claude child pid, poll for respawn, and verify the new pid registers in `coord peers` under the same role. This is the TOD-724 supervisor-loop verification. Use when the user says "test the supervisor", "smoke the respawn", "verify supervision works for role X", "does mesh-spawn actually restart workers", or after changing `/tmp/mesh-workers/<role>.sh`. Args — `<role>` required (e.g. `release`, `builder-q1`, `archivist`), optional `--timeout <secs>` (default 30) for respawn wait.
---

# worker-supervisor-smoke — kill a worker's claude pid and confirm supervisor respawns

Verify the mesh-spawn supervisor loop at `/tmp/mesh-workers/<role>.sh` actually restarts a claude child after SIGTERM, within a deadline, and that the new pid shows up in `coord peers` under the same role. Written after TOD-724 shipped — when the loop was broken, a dead worker silently stayed dead; this skill catches that regression.

## When to use

- User says "smoke test the supervisor", "verify respawn", "test mesh-spawn for <role>", "does supervision work"
- After editing `/tmp/mesh-workers/<role>.sh` or the supervisor wrapper template
- After landing a change to TOD-724 adjacent code (spawn loops, PID tracking, `/tmp/mesh-workers/` structure)
- As a periodic sanity check before relying on auto-respawn in a long mesh session

## When NOT to use

- You want to kill a worker and leave it dead — just `kill <pid>` directly, don't use this.
- You want to test the XREADGROUP/ACK flow (TOD-725/TOD-730) — different layer, different skill (still to be written).
- You want to stress-test with N simultaneous kills — this skill does one worker at a time.
- You want to verify the coord protocol itself — use `/coord-squawk` or read `/tmp/claude-coord/messages/`.

## Procedure

### 1. Parse args / preconditions

- `<role>` (positional, required): e.g. `release`, `builder-q1`, `archivist`. Must correspond to a running wrapper at `/tmp/mesh-workers/<role>.sh` and a pidfile at `/tmp/mesh-workers/<role>.pid`.
- `--timeout <secs>` (default 30): max seconds to wait for respawn. Clamp to 5–300.

Preflight:
```bash
WRAPPER_PID_FILE=/tmp/mesh-workers/${ROLE}.pid
test -f "$WRAPPER_PID_FILE" || { echo "ERROR: no pidfile at $WRAPPER_PID_FILE — role not running under mesh-spawn"; exit 1; }
WRAPPER_PID=$(cat "$WRAPPER_PID_FILE")
kill -0 "$WRAPPER_PID" 2>/dev/null || { echo "ERROR: wrapper pid $WRAPPER_PID not alive — supervisor itself is down"; exit 1; }
```

### 2. Find the current claude child pid

```bash
OLD_CLAUDE_PID=$(pgrep -P "$WRAPPER_PID" claude | head -1)
if [ -z "$OLD_CLAUDE_PID" ]; then
  echo "ERROR: no claude child under wrapper $WRAPPER_PID — either the supervisor is between respawns or the wrapper doesn't exec claude"
  exit 1
fi
echo "old claude pid: $OLD_CLAUDE_PID"
```

### 3. Kill the claude child (SIGTERM)

```bash
kill "$OLD_CLAUDE_PID"
START=$(date +%s)
```

Use SIGTERM, not SIGKILL — the supervisor's respawn trigger is the normal exit path. SIGKILL still works in practice but SIGTERM is the truer smoke case.

### 4. Poll for respawn

```bash
NEW_CLAUDE_PID=""
while [ -z "$NEW_CLAUDE_PID" ] && [ $(( $(date +%s) - START )) -lt "$TIMEOUT" ]; do
  sleep 1
  CANDIDATE=$(pgrep -P "$WRAPPER_PID" claude | head -1)
  if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "$OLD_CLAUDE_PID" ]; then
    NEW_CLAUDE_PID=$CANDIDATE
    break
  fi
  AGE=$(( $(date +%s) - START ))
  echo "  waiting... ${AGE}s elapsed"
done

if [ -z "$NEW_CLAUDE_PID" ]; then
  echo "FAIL: no respawn within ${TIMEOUT}s — supervisor loop broken for role ${ROLE}"
  exit 1
fi

ELAPSED=$(( $(date +%s) - START ))
echo "new claude pid: $NEW_CLAUDE_PID (respawned in ${ELAPSED}s)"
```

### 5. Verify coord registration

Give the new claude process up to `--timeout` additional seconds to call `coord register`:

```bash
DEADLINE=$(( $(date +%s) + TIMEOUT ))
while [ $(date +%s) -lt "$DEADLINE" ]; do
  if ~/.claude/bin/coord peers --json \
       | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if any(p.get('role')=='${ROLE}' and p.get('pid')==${NEW_CLAUDE_PID} for p in d) else 1)"; then
    echo "coord registration confirmed"
    break
  fi
  sleep 1
done
```

If the deadline passes without coord registration, mark as PARTIAL PASS — respawn happened but the new worker didn't register. That's a separate class of bug (usually a missing `coord register` in the worker bootstrap).

### 6. Report

```
worker-supervisor-smoke: role=<role>
  old pid: <OLD>
  new pid: <NEW>
  respawn: <ELAPSED>s (timeout=<TIMEOUT>s)
  coord registration: ok | MISSING
  result: PASS | PARTIAL | FAIL
```

## Examples

```
/worker-supervisor-smoke release
```

Kills the claude child of `/tmp/mesh-workers/release.pid`, waits up to 30s for respawn + coord registration, reports pass/fail.

```
/worker-supervisor-smoke builder-q1 --timeout 60
```

Same for `builder-q1`, with 60s deadline for slower-starting workers (rust-analyzer warmup, etc).

## Safety invariants

- Never kill the wrapper pid itself — only its claude child. Killing the wrapper defeats the test.
- Never call this against a role whose pidfile is missing or stale — fail the preflight.
- Never escalate to SIGKILL in this skill — if SIGTERM doesn't cause a respawn, that's the bug you're looking for.
- Never leave the test half-done: if the respawn poll times out, report FAIL explicitly rather than falling through silently.

## Related tickets

- TOD-724 — supervisor loop (this skill's raison d'être)
- TOD-725 — XREADGROUP heartbeat stall (different layer — handled by `/mesh-cleanup`)
- TOD-730 — ACK-before-execute (different layer — neither this nor `/mesh-cleanup` exercises it)
