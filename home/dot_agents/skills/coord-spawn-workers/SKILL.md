---
name: coord-spawn-workers
description: Spawn N detached tmux Claude Code sessions as coord-protocol workers in thin-context / offload-first mode, verify each one registers via `coord peers --live`, tag them with capabilities, and round-robin dispatch initial work assignments. Thin wrapper around `/tmp/spawn-reverie-worker.sh`. Args — `-n <N>` (default 1, hard cap 3 unless --force), `--force` (bypass cap + quota gate), `--capabilities <csv>`, `--project-dir <path>`, `--assign <TOD-ids>`, `--timeout <seconds>` (default 30), `--dry-run`. CRITICAL mode: refuses spawn when weekly Claude quota >=95% unless --force. Use when the user says "spawn N workers", "launch a fleet", "give me more peers", or "I need workers for TOD-X".
---

# coord-spawn-workers — fleet launcher with registration verification

Launches N detached tmux Claude Code sessions as coord-protocol workers, waits for each to show up in `coord peers --live`, tags them with capabilities, and round-robin dispatches initial work assignments. Built as a thin wrapper around `/tmp/spawn-reverie-worker.sh` — if the underlying script breaks or moves, this skill breaks too, by design.

## When to use

- User asks to "spawn N workers", "launch a fleet", "give me more peers", "spin up workers for TOD-X"
- You're coordinating parallel work across multiple tickets and need 2-8 fresh coord peers with specific capability tags
- A ticket calls for worker capabilities that don't exist in the current peer pool (once TOD-471 capabilities protocol lands)

**Don't** use this when:
- You only need one worker — just invoke `/tmp/spawn-reverie-worker.sh -n 1` directly. The wrapper overhead isn't worth it for N=1.
- `/tmp/spawn-reverie-worker.sh` has been moved, rewritten, or its CLI has changed. The skill is a thin wrapper and will silently misbehave if the underlying script drifts — audit the script first.
- The user wants to attach to or diagnose an existing worker — use `/tmp/spawn-reverie-worker.sh -l` + `tmux attach -t reverie-worker-<N>` instead.
- You're mid-PR work and need an ephemeral scratch session — tmux + `claude` directly is lighter.

## Procedure

### 1. Parse args

- `-n <N>` — worker count. **Default 1. Hard cap 3** unless `--force` is passed. Reject anything higher with a clear error — each worker burns real API budget, and CLAUDE.md CRITICAL mode is the default.
- `--force` — bypass the N>3 hard cap AND the >=95% weekly quota gate. Emits a `[claude · critical-mode-override]` warning so the user can audit Tier-3 burn. Required for any fleet >3 workers or when weekly Claude quota is at/above 95%.
- **Pre-flight quota gate**: the underlying spawn script runs `claude-usage | grep -oP '\d+(?=%)' | head -1` and refuses spawn at >=95% unless `--force`. This is enforced inside `/tmp/spawn-reverie-worker.sh` — the skill does not need to re-check, but should surface the failure clearly.
- `--capabilities <csv>` — capability tags to advertise on each worker's first turn (e.g. `rust.async,dream.place`). Unset = workers register without capability tags.
- `--project-dir <path>` — tmux session cwd. Default `~/projects/reverie`.
- `--assign <TOD-ids>` — comma-separated ticket IDs to dispatch as initial assignments, round-robin across the new workers. Unset = no initial assignment.
- `--timeout <seconds>` — max wait for all workers to appear in `coord peers --live`. Default 30.
- `--dry-run` — print the spawn command, the capability tags, and the per-worker assignment bodies, but don't spawn, don't send, don't touch anything.

### 2. Pre-flight

```bash
SCRIPT=/tmp/spawn-reverie-worker.sh
[[ -x "$SCRIPT" ]] || { echo "FAIL — $SCRIPT missing or not executable"; exit 1; }
command -v tmux    >/dev/null || { echo "FAIL — tmux not in PATH"; exit 1; }
command -v claude  >/dev/null || { echo "FAIL — claude CLI not in PATH"; exit 1; }

# Snapshot existing worker sessions so we can diff after spawn
BEFORE=$(tmux ls 2>/dev/null | awk -F: '/^reverie-worker-/ {print $1}' | sort)
SPAWN_EPOCH=$(date +%s)
```

If `-n` is out of range, abort before touching anything:

```bash
if (( N < 1 )); then echo "FAIL — -n must be >=1 (got $N)"; exit 1; fi
if (( N > 3 )) && ! $FORCE; then echo "FAIL — -n must be 1..3 (got $N); pass --force for fleet >3 (CLAUDE.md CRITICAL)"; exit 1; fi
```

### 3. Spawn workers

Hand off to the existing script. Don't reimplement its tmux logic — the point of this skill is that the script already knows how to do the tmux dance.

```bash
if $DRY_RUN; then
  echo "[dry-run] $SCRIPT -n $N -p $PROJECT_DIR"
else
  "$SCRIPT" -n "$N" -p "$PROJECT_DIR"
fi
```

The script is idempotent — if a `reverie-worker-<N>` tmux session already exists, it skips that slot. **Compare the post-spawn tmux session count against `N`**; if fewer than `N` new sessions appeared, warn the user about skipped slots and adjust the expected-peer count downward before entering the registration wait.

```bash
AFTER=$(tmux ls 2>/dev/null | awk -F: '/^reverie-worker-/ {print $1}' | sort)
NEW_SESSIONS=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER"))
SPAWNED=$(echo "$NEW_SESSIONS" | grep -c .)
if (( SPAWNED < N )); then
  echo "WARN — only $SPAWNED of $N tmux sessions spawned (rest were pre-existing slots)"
fi
```

### 4. Wait for registration

Poll `coord peers --live` every 2 seconds. Match on `role=worker` AND `started_at > SPAWN_EPOCH`. Stop when `SPAWNED` matches appear OR `$TIMEOUT` elapses.

```bash
DEADLINE=$(( SPAWN_EPOCH + TIMEOUT ))
SPAWN_ISO=$(date -u -d "@$SPAWN_EPOCH" +%Y-%m-%dT%H:%M:%SZ)

while (( $(date +%s) < DEADLINE )); do
  REGISTERED=$(coord peers --live 2>/dev/null \
    | jq -r --arg t "$SPAWN_ISO" \
        '.[] | select(.role == "worker" and .started_at > $t) | .session_id')
  COUNT=$(echo "$REGISTERED" | grep -c .)
  (( COUNT >= SPAWNED )) && break
  sleep 2
done
```

Post-loop, if `COUNT < SPAWNED`:
1. List which tmux sessions from `$NEW_SESSIONS` did NOT produce a matching `claude-pid-*` coord session.
2. Print the missing session names and the likely cause (worker still booting, bootstrap prompt rejected, claude CLI auth issue).
3. **Offer cleanup**: `/tmp/spawn-reverie-worker.sh -k` kills all `reverie-worker-*` tmux sessions. Don't run it automatically — ask the user first. Stale coord sessions GC on their own via `last_heartbeat`.

### 5. Tag capabilities (if `--capabilities` set)

For each newly-registered `session_id`, send a coord request asking the worker to advertise capabilities on its next turn:

```bash
for WORKER in $REGISTERED; do
  coord send "$WORKER" request \
    --body "advertise capabilities: $CAPABILITIES (run \`coord cap advertise $CAPABILITIES\` on next turn)"
done
```

**Note on TOD-471**: the `coord cap advertise` subcommand doesn't exist yet. Until TOD-471 (capabilities protocol v0) merges, the worker will see the request, attempt to run the command, fail silently, and move on. Include this step in the skill anyway — when TOD-471 lands, the capability tags will activate automatically with no skill changes needed. Skip entirely in `--dry-run`.

### 6. Dispatch assignments (if `--assign` set)

Round-robin the TOD-IDs across `$REGISTERED`. Each assignment message uses a structured body:

```
work assignment: <TOD-ID>
ticket: https://linear.app/<org>/issue/<TOD-ID>
scope: <one-line summary from ticket title>
suggested worktree: ~/projects/reverie-wt-<todid-lower>
project lock area: <best guess from ticket labels, e.g. reverie-store, reverie-dream>
reply protocol: coord send <dispatcher-session-id> status --body "progress: <pct> | blockers: <...>"
on completion: coord send <dispatcher-session-id> status --body "done: <TOD-ID> | pr: <url>"
```

```bash
IFS=',' read -ra TICKETS <<< "$ASSIGN"
IFS=$'\n' read -rd '' -a WORKERS_ARR <<< "$REGISTERED"
DISPATCHER=$(coord whoami 2>/dev/null | jq -r .session_id)

for i in "${!TICKETS[@]}"; do
  TICKET="${TICKETS[$i]}"
  WORKER="${WORKERS_ARR[$(( i % ${#WORKERS_ARR[@]} ))]}"
  BODY=$(build_assignment_body "$TICKET" "$DISPATCHER")
  if $DRY_RUN; then
    echo "[dry-run] coord send $WORKER request --body <<<$BODY"
  else
    coord send "$WORKER" request --body "$BODY"
  fi
done
```

If `|TICKETS| > |WORKERS|`, workers receive multiple assignments in round-robin order — warn the user this happened so they can redistribute manually if the overlap wasn't intentional.

### 7. Report

Print a table summarizing what happened:

```
worker | session_id       | pid   | capabilities           | assigned  | tmux session       | attach
-------+------------------+-------+------------------------+-----------+--------------------+-------------------------
 1     | claude-pid-65852 | 65852 | rust.async,dream.place | TOD-407   | reverie-worker-1   | tmux attach -t reverie-worker-1
 2     | claude-pid-65867 | 65867 | rust.async,dream.place | TOD-428   | reverie-worker-2   | tmux attach -t reverie-worker-2
 3     | claude-pid-65901 | 65901 | rust.async,dream.place | TOD-438   | reverie-worker-3   | tmux attach -t reverie-worker-3
```

Plus follow-up commands:
- `/tmp/spawn-reverie-worker.sh -l` — list all live worker tmux sessions
- `/tmp/spawn-reverie-worker.sh -k` — kill all worker tmux sessions
- `coord peers --live` — see the full peer roster including workers
- `coord inbox <session-id>` — check what a specific worker has received

## Safety invariants

- **Never spawn more than 3 workers without `--force`.** Default is 1. CLAUDE.md CRITICAL mode is the default operating posture; every worker is a full Claude Code session burning real Tier-3 budget.
- **Honor the quota gate.** If `claude-usage` reports >=95% weekly, the underlying script refuses spawn unless `--force`. With `--force`, surface the `[claude · critical-mode-override]` warning to the user verbatim — do NOT swallow it.
- **Workers boot in thin-context / offload-first mode.** They do NOT preload CLAUDE.md, do NOT explore the repo, and route all generative work through `~/.local/bin/anchor-offload` (Tier 1 → Tier 2). Don't extend the bootstrap with "read X first" — that defeats the entire point of the architecture.
- **Never reuse worker session IDs.** The underlying spawn script already skips existing `reverie-worker-<N>` slots; the skill verifies the spawn count matches expectations and warns on mismatch.
- **Never leave stale coord sessions on failure.** On registration timeout or partial failure, explicitly print the `/tmp/spawn-reverie-worker.sh -k` cleanup command and ask before running it. Stale coord session records GC via `last_heartbeat` but stale tmux sessions do not.
- **Never leak credentials in the bootstrap prompt.** The spawn script already env-scopes `CLAUDE_COORD_ROLE=worker COORD_ROOT=/tmp/claude-coord` and nothing else. Do NOT extend it with any `*KEY*` / `*TOKEN*` / `*SECRET*` env vars. If capability tagging needs auth, it belongs inside the worker's own session, not the bootstrap env.
- **Always honor `--dry-run`.** Print the spawn command, the full capability tag list, and the per-worker assignment bodies — but do not spawn, send, or mutate any tmux / coord state.
- **Never bypass the `coord register` step.** If a worker's tmux session exists but it never appears in `coord peers --live`, it is NOT a coord peer and must not receive assignments. Workers that fail to register are reported as missing and left alone.
- **Never send assignments to workers outside the newly-spawned set.** Round-robin only over `$REGISTERED`, never over the full peer list — otherwise we'd accidentally dispatch to unrelated peer sessions.

## Future extensions

- **TOD-471 integration** — once `coord cap advertise` lands, step 5 activates automatically. No skill change needed, but worth adding a `--wait-for-capabilities` flag that polls `coord peers --live` for the capability tags to appear before declaring success.
- **Heterogeneous fleets** — right now all N workers get the same `--capabilities` string. A future `--fleet-spec <json>` could specify per-worker tags (e.g. 2x `rust.async`, 1x `audit.code-review`, 1x `dream.place`).
- **Assignment templates** — step 6's body template is hardcoded. A `~/.claude/templates/work-assignment.md` file would let users customize without editing the skill.
- **Auto-worktree** — the assignment body suggests a worktree path but doesn't create it. A follow-up skill `coord-assign-with-worktree` could chain `wt` + `coord-spawn-workers` + initial assignment dispatch.
- **Budget guardrail** — read `~/.claude/coord/budget.json` (if it exists) and reject spawns that would exceed a daily worker-hour cap. Pairs with a separate `coord-budget` skill.
