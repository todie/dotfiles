---
name: deploy-reverie
description: >
  Build, install, and verify the reverie daemon (reveried) + cortex CLI
  + reverie-bench from a clean main. Idempotent; safe to re-run. Use when
  merged PRs need to land on the running daemon. Handles the stop-daemon,
  free-busy-binary, install, restart, /health smoke sequence.
allowed-tools:
  - Bash
tags: [deploy, reveried, install, systemd]
---

# Deploy reverie

## Usage

`/deploy-reverie` — fully idempotent, from anywhere. Defaults to `--release`,
keeps the systemd user unit running, smoke-tests `/health` on 7437.

Flags (pass after the skill name):
- `--skip-smoke`   don't curl /health after restart
- `--release`      (default) ship optimized binary
- `--dev`          skip optimizations (faster build, slower runtime)

## Steps

1. **Check freshness** — compare the oldest installed binary mtime (across
   reveried, cortex, reverie-bench) vs the latest `origin/main` commit.
   Skip build only if ALL three are current. One binary missing or stale
   triggers a full rebuild.
   ```bash
   git -C ~/projects/reverie fetch origin main -q
   oldest=$(stat -c %Y ~/.local/bin/reveried ~/.local/bin/cortex ~/.local/bin/reverie-bench 2>/dev/null | sort -n | head -1)
   oldest=${oldest:-0}
   latest_commit_mtime=$(git -C ~/projects/reverie log origin/main -1 --format=%ct)
   [ "$oldest" -ge "$latest_commit_mtime" ] && echo "already current" && exit 0
   ```

2. **Free busy binaries before install** — cortex in particular is commonly
   held open by live tmux sessions. The installer refuses to overwrite a
   mapped executable.
   ```bash
   for bin in cortex reveried reverie-bench; do
     path=$HOME/.local/bin/$bin
     pid=$(lsof -t "$path" 2>/dev/null | head -1)
     [ -n "$pid" ] && kill "$pid" && sleep 1
   done
   ```

3. **Run the installer** — `scripts/install-reverie.sh` handles cargo build,
   systemd stop/start, binary swap, /health smoke.
   ```bash
   cd ~/projects/reverie
   bash scripts/install-reverie.sh --skip-redis-check
   ```

4. **Verify** — daemon /health + cortex sanity.
   ```bash
   curl -sf http://127.0.0.1:7437/health | jq -c '{status, version, db_healthy}'
   cortex --version                     # confirms binary swap worked
   cortex health --json 2>/dev/null | jq -c '{daemon, redis, coord}' || true
   ```

5. **Report** — one line: reveried version, cortex version, peer count,
   any warnings.

## Notes

- The installer is the source of truth. Don't manually run `cargo install`
  or copy binaries — the script enforces stop/swap/start ordering and
  handles busy-binary cases.
- If a user-level systemd unit is missing, the installer creates it. Use
  `systemctl --user status reveried` to check.
- If a build fails mid-run, `~/.local/bin/*` is untouched (atomic swap).
