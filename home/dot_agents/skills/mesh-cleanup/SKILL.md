---
name: mesh-cleanup
description: Identify and kill stale mesh workers (heartbeat >120s but pid still alive — the TOD-725 XREADGROUP stall case) and sweep orphan `/tmp/claude-coord/messages/inbox-claude-pid-*` directories for pids that are no longer registered in coord, without touching live workers, worktrees, or unmerged branches. Use when the user says "clean up stale workers", "kill the zombies", "sweep orphan inboxes", "the mesh is cluttered", or "purge dead peers". Args — optional `--dry-run` to print what would be killed/swept without acting, optional `--keep <role,role>` to whitelist specific roles from the kill pass (useful for a pinned release worker or hypervisor).
---

# mesh-cleanup — kill stale workers + sweep orphan inboxes

Remove dead weight from the reverie mesh in one shot: SIGTERM→SIGKILL any worker whose heartbeat has stalled past 120s (the TOD-725 failure mode where a claude pid is still alive but the XREADGROUP call wedged), and `rm -rf` coord inbox directories whose pid is no longer in the peer list. Leaves worktrees and worker branches alone — that's the `/wt` / `worktree-pr` domain.

## When to use

- User says "clean up the mesh", "kill stale workers", "sweep orphan inboxes", "purge dead peers", "the mesh is cluttered"
- After a TOD-725-style heartbeat stall where claude pids look alive to `ps` but haven't heartbeated in minutes
- After a crashed mesh-spawn supervisor loop leaves `inbox-claude-pid-NNNN` directories behind for pids that no longer exist
- Before a release or merge, to make `coord peers` honest again

## When NOT to use

- You want to kill **live** peers — that's `kill` + `coord dereg`, not this. This skill explicitly refuses to touch heartbeat-<60s peers.
- You want to remove worktrees or branches — use `/wt` cleanup or `git worktree remove` directly. This skill never touches `git worktree list` output or `worker/*` branches.
- You want to clear Redis stream backlog (`tasks:queue:default`) — that's a separate XTRIM/XACK workflow, not in scope here.
- You want to nuke all coord state (sessions + inboxes + locks) — use `coord reset` or manual `rm -rf /tmp/claude-coord/` with confirmation.

## Procedure

### 1. Parse args / preconditions

- `--dry-run`: print the classification + what would be killed/swept but make zero state changes. Default: off.
- `--keep <role,role>`: csv of role names to skip in the kill pass. Example: `--keep hypervisor,release`. Still classified + reported, just not killed. Default: empty.
- Preflight:
  ```bash
  test -x ~/.claude/bin/coord || { echo "ERROR: coord binary missing at ~/.claude/bin/coord"; exit 1; }
  test -d /tmp/claude-coord/messages || { echo "no coord messages dir — nothing to sweep"; }
  ```

### 2. Classify peers

```bash
NOW=$(date -u +%s)
~/.claude/bin/coord peers --json 2>/dev/null \
  | python3 -c '
import sys, json, os, time, subprocess
peers = json.load(sys.stdin)
now = int(time.time())
for p in peers:
    pid = p.get("pid")
    hb = p.get("last_heartbeat_epoch") or 0
    age = now - hb
    role = p.get("role", "unknown")
    alive = False
    if pid:
        try:
            os.kill(int(pid), 0)
            alive = True
        except (ProcessLookupError, PermissionError, ValueError):
            alive = False
    if alive and age < 60:
        cls = "LIVE"
    elif alive and age > 120:
        cls = "STALE"
    else:
        cls = "DEAD" if not alive else "AGING"
    print(f"{cls}\t{p.get(\"session_id\")}\t{pid}\t{role}\t{age}s")
'
```

Classification rules:
- **LIVE** — heartbeat <60s, pid alive. Leave alone.
- **AGING** — heartbeat 60–120s, pid alive. Leave alone, warn in report.
- **STALE** — heartbeat >120s, pid alive. Kill candidate (TOD-725).
- **DEAD** — pid gone. Nothing to kill; coord record will self-clear on next sweep.

### 3. Kill STALE peers

For each `STALE` peer whose role is NOT in `--keep`:

```bash
if [ -z "$DRY_RUN" ]; then
  kill "$PID" 2>/dev/null || true      # SIGTERM
  sleep 2
  if kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID" 2>/dev/null || true # SIGKILL escalation
    echo "  SIGKILL escalated for $PID"
  fi
fi
```

Record each kill as `killed <session_id> pid=<pid> role=<role> age=<age>`.

### 4. Sweep orphan inbox directories

```bash
RUNNING_PIDS=$(~/.claude/bin/coord peers --json | python3 -c '
import sys, json
print(" ".join(str(p.get("pid")) for p in json.load(sys.stdin) if p.get("pid")))
')
for dir in /tmp/claude-coord/messages/inbox-claude-pid-*; do
  [ -d "$dir" ] || continue
  pid=$(basename "$dir" | sed 's/^inbox-claude-pid-//')
  if echo " $RUNNING_PIDS " | grep -q " $pid " || kill -0 "$pid" 2>/dev/null; then
    continue  # still registered or still alive — keep
  fi
  if [ -n "$DRY_RUN" ]; then
    echo "would sweep $dir"
  else
    rm -rf "$dir"
    echo "swept $dir"
  fi
done
```

A pid counts as "keep" if EITHER it's in `coord peers` OR `kill -0` says the process is alive. Both checks are cheap and the union avoids a race where a peer has registered but its first heartbeat hasn't landed yet.

### 5. Explicit non-actions

Do NOT:
- Run `git worktree list` / `git worktree remove`
- Touch `worker/*` branches
- Clear Redis streams (`tasks:queue:default` etc.)
- Delete coord session records under `/tmp/claude-coord/sessions/` (coord self-prunes these)
- Touch `/tmp/claude-coord/locks/` — use `/orphan-lock-clean` for that

### 6. Report

```
mesh-cleanup: 3 LIVE, 1 AGING, 2 STALE killed, 4 DEAD, 7 orphan inboxes swept
  killed claude-pid-41038 pid=41038 role=archivist age=347s
  killed claude-pid-41120 pid=41120 role=builder-q1 age=201s
  swept /tmp/claude-coord/messages/inbox-claude-pid-39001
  swept /tmp/claude-coord/messages/inbox-claude-pid-39112
  ...
```

If `--dry-run`, prefix the report with `DRY RUN — no changes made`.

## Examples

```
/mesh-cleanup --dry-run
```

Shows what would be killed + swept, no state change.

```
/mesh-cleanup --keep hypervisor,release
```

Sweeps everything stale except the hypervisor and release workers, even if they're heartbeat-stalled.

## Safety invariants

- Never kill a peer with heartbeat <120s. LIVE and AGING are untouchable.
- Never sweep an inbox dir whose pid is alive OR registered in coord. Both checks required.
- Never touch worktrees, branches, Redis streams, or locks.
- Always honor `--dry-run`.
- Always escalate SIGTERM → SIGKILL with a 2s gap — never bypass TERM.

## Related tickets

- TOD-724 — supervisor loop that spawns claude pids
- TOD-725 — XREADGROUP heartbeat stall (the STALE case this skill exists for)
- TOD-730 — ACK-before-execute (adjacent but separate cleanup domain)
