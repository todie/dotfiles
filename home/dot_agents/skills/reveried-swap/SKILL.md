---
name: reveried-swap
description: Rebuild reveried from a git ref, pause-world the running daemon, swap the binary at ~/.local/bin/engram, verify, and unpause. Serializes concurrent swaps via a kernel flock (auto-released on process death) and rolls back on smoke failure. Use when the user wants to update the running reveried binary to pick up new fixes or features on main (or any other branch). Args — optional `<ref>` (default `origin/main`) and optional `--force` to skip the pre-swap diff audit.
---

# reveried-swap — safe daemon binary swap

Rebuild reveried from a git ref, pause the running daemon, swap the binary at `~/.local/bin/engram`, verify it starts, unpause, and release the lock. Designed around the "daemon is in use right now" case — never drops in-flight requests, always leaves you with either the new binary or the old one intact.

## When to use

- User asks to "update reveried", "swap the daemon", "rebuild the binary", or "apply the new fixes"
- `reveried` is missing a known store / HTTP / MCP fix and the running binary will silently misbehave until swapped
- A feature you need (new route, new MCP tool, schema fix) lives on main but not in the running binary
- After a review + merge of a daemon-affecting PR

**Don't** use this when:
- The change is config-only — swap wastes time. Use `reveried reload` (TOD-429) once it lands, or edit `~/.config/reveried/config.toml` if it's already config-backed
- The change is in a crate that isn't linked into reveried (e.g. `reverie-bench` is a separate binary)
- You're mid-PR work — build + test in a worktree first, don't swap experimental binaries into `~/.local/bin/engram`
- The user hasn't reviewed the diff (unless `--force`)

## Procedure

### 1. Parse args

- First positional arg: git ref to build from. Default `origin/main`.
- `--force`: skip the pre-swap audit + confirmation.
- `--branch <name>`: alias for positional ref.
- `--dry-run`: do everything except the actual `cp` and `unpause`.
- `--no-rebuild`: swap from an existing target binary at `target/release/reveried` instead of building.

### 2. Pre-swap audit (unless `--force`)

Run a diff between the currently installed binary's build-time commit and the target ref, classify what's changing:

```bash
BIN=~/.local/bin/engram
BIN_MTIME=$(stat -c %Y "$BIN")
cd ~/projects/reverie
git fetch --quiet
# List commits newer than the binary, grouped by impact
git log <ref> --since="@$BIN_MTIME" --oneline
```

Bucket commits into:

- **🔴 Requires swap** — touches `crates/reveried/`, `crates/reverie-store/`, `crates/reverie-gate/`, `crates/reverie-dream/`, `crates/reverie-sync/`, or `crates/reverie-chunk/`
- **🟠 CLI/client only** — touches `crates/reveried/src/main.rs` or `client.rs` (daemon runtime unchanged but user-facing commands differ)
- **🟢 No swap needed** — `docs/`, `.github/`, `README.md`, bench-only crates

Print the table and pause for confirmation unless `--force` is set. If there are zero 🔴 commits, warn and ask if the swap is still wanted.

### 3. Serialization — kernel flock (taken around the critical section)

Concurrent swaps are serialized with a kernel `flock` on
`/var/lock/reverie-engram-serve.lock`. The lock is acquired by wrapping the
**critical section (steps 7–9)** in a single flock'd shell block — see step 7.
Properties that make this strictly better than TTL locks: the kernel releases
it automatically when the holding process exits or crashes (no orphan locks,
no steal protocol), and a second session attempting a swap blocks up to 600s
then aborts cleanly. A breadcrumb line (`pid`, timestamp, target ref) is
written into the lock file purely for observability — it is NOT the lock.

### 4. Build

Build from a **clean worktree** (not the main checkout, which may have uncommitted user work):

```bash
BUILD_DIR=~/projects/reverie-wt-swap-$(date +%s)
git worktree add --detach "$BUILD_DIR" <ref>
cd "$BUILD_DIR"
cargo build --release -p reveried 2>&1 | tail -20
```

Fail loudly on build errors. Never proceed with a stale binary.

### 5. Smoke test the new binary

Before overwriting anything, verify the new binary at least starts and responds on a temp port:

```bash
NEWBIN="$BUILD_DIR/target/release/reveried"
$NEWBIN serve --port 17438 --db /tmp/reveried-swap-smoke.db &
SMOKE_PID=$!
sleep 2
curl -sf http://127.0.0.1:17438/health | jq -e '.status=="ok"' || {
  kill $SMOKE_PID 2>/dev/null
  echo "SMOKE FAIL — new binary /health not responding; aborting swap"
  exit 1
}
kill $SMOKE_PID 2>/dev/null
rm -f /tmp/reveried-swap-smoke.db
```

### 6. Back up the current binary

```bash
BACKUP=~/backups/engram/engram-$(date -u +%Y%m%dT%H%M%SZ).bak
mkdir -p ~/backups/engram
cp "$BIN" "$BACKUP"
```

Never skip this step. A swap that goes wrong without a backup is unrecoverable.

### 7. Critical section — pause, swap, restart, verify (under flock)

Steps 7–9 run as ONE flock'd shell block so the lock is held for the whole
mutation and vanishes with the process no matter how it exits:

```bash
flock -w 600 /var/lock/reverie-engram-serve.lock bash -euo pipefail -c '
  echo "$$ $(date -Is) swap-to-<ref>" > /var/lock/reverie-engram-serve.lock.info
  # --- steps 7-9 body goes here (pause → install → restart → verify) ---
' || { echo "another swap holds the lock (waited 600s) — ABORT"; exit 1; }
```

Pause the running daemon (inside the block):

```bash
~/.local/bin/engram pause --reason "reveried swap to <ref>" || true
# Allow in-flight requests to drain
sleep 3
```

If the pause subcommand doesn't exist on the old binary (pre-TOD-412), skip this and accept the risk of dropping in-flight requests. Warn the user if that's the case.

### 8. Atomic swap

Use `install` (atomic rename) not `cp` (not atomic, may leave a half-written binary if interrupted):

```bash
install -m 755 "$NEWBIN" "$BIN"
```

### 9. Verify the new binary is live

```bash
~/.local/bin/engram --help >/dev/null || {
  echo "POST-SWAP FAIL — new binary at $BIN not executable; rolling back"
  cp "$BACKUP" "$BIN"
  exit 1   # flock releases automatically on exit
}
```

If the running daemon is using the SAME binary path (`~/.local/bin/engram`), the swap affects the file but the running process is still the old binary (Linux mmaps the executable pages). The process needs to exit + restart to load new code. Options:

- **SIGHUP / reload** — only works if TOD-429 hot-reload has landed
- **SIGUSR2 / fork-exec** — only works if SO_REUSEPORT cutover is implemented
- **SIGTERM + restart** — works today, brief downtime window

For now, use SIGTERM + restart:

```bash
pgrep -f "engram serve" | xargs -r kill -TERM
sleep 2
nohup "$BIN" serve >/dev/null 2>&1 &
disown
sleep 2
curl -sf http://127.0.0.1:7438/health | jq -e '.status=="ok"' || {
  echo "POST-RESTART FAIL — daemon not responding; rolling back"
  pgrep -f "engram serve" | xargs -r kill -TERM
  cp "$BACKUP" "$BIN"
  nohup "$BIN" serve >/dev/null 2>&1 &
  disown
  exit 1   # flock releases automatically on exit
}
```

### 10. Unpause

Only reach here if `/health` is green post-restart:

```bash
~/.local/bin/engram unpause || true
```

### 11. Lock release

Nothing to do — the flock died with the critical-section shell. If you want
proof: `flock -n /var/lock/reverie-engram-serve.lock true && echo free`.

### 12. Clean up the temp worktree (optional)

```bash
cd ~
git -C ~/projects/reverie worktree remove "$BUILD_DIR"
```

### 13. Report

Print a summary:
- Built from: `<ref>` (commit `<short-hash>`)
- Backed up: `<backup-path>`
- Pre-swap commits applied: `<count>`
- Categories: `<counts by bucket>`
- Duration: `<seconds>`
- New binary size: `<bytes>`
- `/health` response: OK
- Swap lock: auto-released (flock)

## Rollback procedure (manual)

If the swap goes wrong AND the automated rollback didn't fire, the user can always:

```bash
pgrep -f "engram serve" | xargs -r kill -TERM
cp ~/backups/engram/engram-<timestamp>.bak ~/.local/bin/engram
nohup ~/.local/bin/engram serve >/dev/null 2>&1 &
disown
# No lock cleanup needed — the flock died with whatever process held it.
```

The MVP-A cutover rollback binary (`~/backups/engram/engram-go-binary-20260407.bak`) is the nuclear option — it's the last-known-good Go engram from before the Rust cutover. Only use if every Rust build is broken.

## Safety invariants

- **Never** `cp` (non-atomic). Always `install -m 755` (atomic rename).
- **Never** skip the backup. No exceptions.
- **Never** run the critical section outside the flock unless `--force` AND the user has typed "i know what im doing".
- **Never** swap while a long-running MCP call is in flight without pausing first.
- **Never** overwrite `~/backups/engram/engram-go-binary-20260407.bak` — that's the MVP-A rollback capsule.
- **Always** smoke-test the new binary on a temp port + temp DB before touching the production binary.
- **Always** verify the post-restart `/health` before unpausing.
- **Always** offer a rollback if any verification step fails.

## Future extensions

- **Hot reload** (TOD-429) — once SIGHUP config reload + SIGUSR2 binary cutover land, this skill's "restart" step becomes a signal instead of kill+nohup. Swap can then be zero-downtime.
- **Canary port** — bind new binary on a second port (e.g. 7439), proxy a fraction of traffic, compare, then flip. Requires a small load balancer; probably overkill for single-host.
- **Lock checkpoint** — snapshot DB state before swap; rollback restores the snapshot on abort. Only matters if a swap can corrupt the DB, which the current schema design guards against.
- **Dry-run diff report** — expand `--dry-run` to print a full changelog and an impact map without touching anything.
