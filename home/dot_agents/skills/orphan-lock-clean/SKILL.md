---
name: orphan-lock-clean
description: Inspect a coord lock, verify the owner pid is dead, and reclaim it via in-place Write to record.json + owner (no rm, so it works without rm allowlist entries). Use when `coord lock <resource>` hangs on a dead peer and `coord steal` refuses because the TTL hasn't expired yet. Args — required `<resource>` (e.g. `claude-config`, `engram-serve`, `pr-merge-queue`, `main-branch`, `cargo-build`, `project:<name>[:<area>]`), optional `--reason <string>`, `--ttl <seconds>` (default 600), `--dry-run`, `--force`.
---

# orphan-lock-clean — reclaim a coord lock from a dead owner

Inspect a coord lock at `/tmp/claude-coord/locks/<resource>/`, prove the holder is dead (pid gone AND session heartbeat stale), and take over the lock by overwriting `record.json` + `owner` in place. Designed for the "previous session died mid-TTL" case where `coord steal` refuses because the lock isn't formally expired.

## When to use

- `coord lock <resource>` hangs because a dead peer still "holds" it
- `coord steal <resource>` refuses because TTL hasn't expired (`is_lock_owner_alive() && !lock_is_steelable()` — there's no force path for "dead owner within TTL")
- You need the lock before proceeding with a blocked operation: settings edits, cargo build, daemon swap, PR merge, main checkout
- The holding session's pid is actually gone (confirm with `kill -0`) and its session record is either missing or has a stale heartbeat

**Don't** use this when:

- The lock was acquired less than ~60s ago — the holder might just be slow. Wait first.
- The owner pid is still alive — coordinate via `coord send <session_id>` instead of stealing
- You own the lock yourself — use `coord unlock <resource>`
- The TTL has already expired AND the cooldown has passed — use `coord steal <resource>`, which is the protocol-correct path
- The resource name isn't a known lock (`main-branch`, `pr-merge-queue`, `cargo-build`, `claude-config`, `engram-serve`, or `project:*`) — warn and ask the user before touching anything unfamiliar

## Procedure

### 1. Parse args

- First positional arg: `<resource>` (required). e.g. `claude-config`.
- `--reason <string>`: reason to record in the new lock (default: `"orphan steal: previous owner dead"`).
- `--ttl <seconds>`: new lock TTL (default `600`).
- `--dry-run`: inspect + report without stealing.
- `--force`: steal even if the owner appears alive. Requires an extra explicit confirmation.

### 2. Check the lock directory exists

```bash
LOCK_DIR=/tmp/claude-coord/locks/<resource>
[ -d "$LOCK_DIR" ] || { echo "lock not held: $LOCK_DIR does not exist"; exit 0; }
[ -f "$LOCK_DIR/record.json" ] || {
  echo "MALFORMED: $LOCK_DIR exists without record.json"
  # abort unless --force
}
```

### 3. Read the lock record

Use the Read tool on `/tmp/claude-coord/locks/<resource>/record.json`. Extract:

- `owner_session_id`
- `owner_pid`
- `acquired_at`
- `expires_at`
- `reason`

Also Read `/tmp/claude-coord/locks/<resource>/owner` (plain-text single-line session id) as a sanity check — it should match `owner_session_id`.

### 4. Check owner liveness

Two independent checks — owner is only ALIVE if BOTH pass.

**pid check:**

```bash
kill -0 <owner_pid> 2>/dev/null && PID_ALIVE=yes || PID_ALIVE=no
```

**heartbeat check:**

```bash
SESSION_FILE=/tmp/claude-coord/sessions/<owner_session_id>.json
```

If the session file doesn't exist, heartbeat counts as STALE. If it exists, Read it and check `last_heartbeat`:

```
stale = (now - last_heartbeat) > 300s
```

Classify:

- **ORPHAN** — `PID_ALIVE=no` OR heartbeat stale OR session file missing. Safe to steal.
- **LIVE** — `PID_ALIVE=yes` AND heartbeat fresh. Abort (unless `--force`).
- **EXPIRED** — owner is dead AND `now > expires_at + STEAL_COOLDOWN_SEC`. Recommend `coord steal` instead; this skill isn't needed.

### 5. Report the liveness finding

Print a block like:

```
Lock: <resource>
Current owner session: <owner_session_id>
Current owner pid: <owner_pid>
Owner pid alive: <yes|no>
Session heartbeat: <iso-timestamp> (<Xs ago>)
Heartbeat stale (>300s): <yes|no>
TTL: acquired=<iso>, expires=<iso>, remaining=<duration>
Verdict: <ORPHAN — safe to steal | LIVE — abort | EXPIRED — use `coord steal` instead>
```

### 6. If ORPHAN and not `--dry-run` — steal via in-place Write

Get the current session's own identity:

```bash
MY_SID=$(~/.claude/bin/coord status | head -5 | grep session_id | awk '{print $2}')
# pid: prefer reading own session record at /tmp/claude-coord/sessions/$MY_SID.json (field: pid)
```

Compute timestamps:

```
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EXPIRES_ISO=$(date -u -d "+<ttl> seconds" +%Y-%m-%dT%H:%M:%SZ)
```

Read the existing `record.json` first (the Write/Edit tool requires it, and it also catches the case where the lock changed owners between inspection and steal). Then overwrite in place:

```json
{
  "schema": 1,
  "resource": "<resource>",
  "owner_session_id": "<MY_SID>",
  "owner_pid": <MY_PID>,
  "acquired_at": "<NOW_ISO>",
  "expires_at": "<EXPIRES_ISO>",
  "reason": "<args.reason> (stolen from dead pid <old_pid> / session <old_sid>)"
}
```

Then Read and Write `/tmp/claude-coord/locks/<resource>/owner` — single line, `<MY_SID>`, newline-terminated.

**Never use `rm`** on these paths. In-place Write keeps the directory structure intact and doesn't depend on any `Bash(rm -rf /tmp/claude-coord/locks/*)` allowlist entry.

### 7. If LIVE — abort

Print the live owner's pid + heartbeat age + reason and exit non-zero. Suggest:

- `coord send <owner_session_id> "<why you need the lock>"` to coordinate
- wait for the owner to `coord unlock`
- re-run with `--force` only if you're certain the listed peer is doing nothing useful

`--force` additionally requires a confirmation prompt that prints the live owner's pid, session id, heartbeat age, and reason. Never silently steal a live lock.

### 8. If EXPIRED — recommend `coord steal`

Print a one-liner:

```
TTL already expired and cooldown elapsed — use `coord steal <resource>` instead. That's the protocol-correct path for expired locks; this skill is only for the mid-TTL dead-owner case.
```

Exit 0 without touching anything.

### 9. Post-steal verification + report

Re-Read `record.json` to confirm the new values landed:

```
Lock reclaimed: <resource>
Old owner: <old_sid> / pid <old_pid> (<verdict reason>)
New owner: <MY_SID> / pid <MY_PID>
Acquired at: <NOW_ISO>
Expires at: <EXPIRES_ISO>
TTL: <ttl>s
Reason: <new reason>
```

The dead session's record at `/tmp/claude-coord/sessions/<old_sid>.json` is **left alone** — cleaning up orphaned session files is a separate concern and not this skill's job.

## Safety invariants

- **Never steal a live lock** without `--force` AND an explicit confirmation prompt showing the live owner's pid + heartbeat.
- **Never use `rm -rf` on lock directories.** In-place Write is the whole point — it's safer AND doesn't require `Bash(rm ...)` allowlist permissions.
- **Always Read before Write.** The Edit/Write tools require it, and it detects the race where the lock changed owners between step 3 and step 6.
- **Never steal unfamiliar resources.** If the name isn't in the CLAUDE.md locks table or doesn't match `project:*`, warn the user and get confirmation.
- **Always preserve the TTL chain correctly.** New `acquired_at` is **now**, new `expires_at` is **now + ttl** — never derive from the old record's fields.
- **Never delete the dead owner's session file.** That's separate housekeeping; keep this skill scoped to the lock itself.
- **Never skip the heartbeat check.** A pid can be reused quickly on Linux — `kill -0` alone isn't enough proof of death.

## Background

The coord protocol's `coord steal` logic is `is_lock_owner_alive() && !lock_is_steelable()` — the owner must be dead AND the lock must have passed its TTL + `STEAL_COOLDOWN_SEC`. When a session dies DURING the TTL window, `coord steal` refuses and the lock is stuck for ~70 minutes. This skill is the workaround until `coord force-steal` ships as a first-class subcommand.

Lock record format (6 fields + schema): `schema=1`, `resource`, `owner_session_id`, `owner_pid`, `acquired_at` (ISO-8601 UTC), `expires_at` (ISO-8601 UTC), `reason`. The `owner` file is a single-line plain-text session id.

Known resources (from CLAUDE.md):

- `main-branch` — lost-work prevention on `git checkout main`
- `pr-merge-queue` — GitHub async-merge races
- `cargo-build` — `target/` corruption on main worktree
- `claude-config` — hook/settings races (writes to `~/.claude/*`)
- `engram-serve` — daemon cutover safety
- `project:<name>` / `project:<name>:<area>` — project-scoped locks (TOD-471)

Relevant binary: `~/.claude/bin/coord`.

## Future extensions

- **`coord force-steal` subcommand** — once landed, this skill becomes a thin wrapper that calls the binary instead of touching files directly.
- **Heartbeat-only mode** — detect and clean up locks whose holder session is just `last_heartbeat`-stale even if the pid somehow still resolves (zombie processes).
- **Batch mode** — scan `/tmp/claude-coord/locks/*` and reclaim all orphans in one pass, with a single confirmation.
- **Dead-session cleanup pairing** — optional post-steal hook to GC the dead owner's `/tmp/claude-coord/sessions/<sid>.json` file if nothing else references it.
