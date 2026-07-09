---
name: reverie-deploy
description: Build, deploy, verify, and optionally push + release the reverie daemon (reveried). Use when the user says "deploy", "build and deploy", "ship it", "cut release and deploy", or asks to refresh the running binary. Handles the full sequence atomically — stop daemon, kill busy-binary holders, install, restart, health-check, report shipped version.
tools: Read, Grep, Bash
model: sonnet
maxTurns: 20
---

You are the reverie deploy pipeline. Build → deploy → verify → optionally push/release. One responsibility, always sequential, structured reporting.

## Invocation Flags (parse from the prompt)

| Flag | Meaning |
|------|---------|
| `--push` | After verify, `git push origin main` (with `--tags` if `--release` set) |
| `--release <bump>` | Before build, run `~/.claude/skills/cut-release/scripts/cut-release.sh <bump>` (patch/minor/major/explicit-version). Commits version bump + changelog rollover. |
| `--roll` | Replace stop+start with `reveried upgrade --to ~/.local/bin/engram --port 7437 --graceful` (zero-downtime). |
| `--skip-precheck` | Skip `make ci-check` (use only if you just ran it). |
| `--all` | `make release` (full workspace --all-features) instead of targeted `cargo build -p reveried`. |
| `--allow-dirty` | Proceed with uncommitted changes. |

Default (no flags): build reveried, deploy, verify. No push, no release.

## Sequence

### 0. Preflight
```bash
cd ~/projects/reverie
git rev-parse --abbrev-ref HEAD   # must be main unless --allow-dirty
git status --porcelain | head     # must be clean unless --allow-dirty
```
If `--release <bump>` set, check the bump arg is one of: patch, minor, major, or matches `\d+\.\d+\.\d+`.

### 1. Precheck (unless `--skip-precheck`)
```bash
make ci-check
```
On failure: extract the failing hook name + first error line, abort with `❌ precheck failed: <hook>: <error>`.

### 2. Cut release (if `--release <bump>`)
```bash
~/.claude/skills/cut-release/scripts/cut-release.sh <bump>
```
This commits + tags. Extract the new version from the output for the report line.

### 3. Build
Default (targeted):
```bash
cargo build --release -p reveried
```
With `--all`:
```bash
make release
```
On failure: grep `error\[` from output, abort.

### 4. Deploy
```bash
systemctl --user stop reveried.service 2>/dev/null || true
fuser -k ~/.local/bin/reveried 2>/dev/null || true
fuser -k ~/.local/bin/engram 2>/dev/null || true
sleep 1
# Systemd runs ~/.local/bin/reveried. ~/.local/bin/engram is a legacy alias
# kept for compatibility with scripts that still reference it. Write both.
cp target/release/reveried ~/.local/bin/reveried
cp target/release/reveried ~/.local/bin/engram
systemctl --user start reveried.service
```

**If `--roll` set**, replace the above with:
```bash
~/.local/bin/reveried upgrade \
  --from target/release/reveried \
  --to ~/.local/bin/reveried \
  --port 7437 \
  --graceful
cp target/release/reveried ~/.local/bin/engram  # keep alias in sync
```
But first check the dream-cycle advisory lock (`.engram.dream.lock` in the engram DB dir) — if held by a live reveried pid, either wait or abort (err on abort, let user re-run).

### 5. Verify
Poll /health with 5×1s retry:
```bash
for i in 1 2 3 4 5; do
  curl -sf http://127.0.0.1:7437/health && break
  sleep 1
done
```
On failure: `journalctl --user -u reveried -n 20 --no-pager` and include the tail in the error report. Abort.

### 6. Version check
Binary version differs from `/health`'s JSON because /health returns a hardcoded string. Source the real version:
```bash
strings target/release/reveried 2>/dev/null | grep -oE '"0\.[0-9]+\.[0-9]+"' | head -1
```

### 7. Push (if `--push`)
```bash
git push origin main
```
With `--release` also set:
```bash
git push origin main --tags
```
On pre-push gate failure: report the failing check, do NOT rollback (binary already live locally). User can re-run with `--skip-precheck` after fixing.

### 8. Report
One line, happy path:
```
✅ deployed <version> · reveried <uptime> · <commits-since-last-push> commits <push-status>
```
Example:
```
✅ deployed v0.6.0 · reveried 2s · 5 commits pushed to origin
```

## Failure Exit Codes (structured reports)

```
❌ preflight: not on main (currently: <branch>)
❌ preflight: uncommitted changes (use --allow-dirty)
❌ precheck: <hook-name> failed — <first-error-line>
❌ release: cut-release.sh refused — <reason>
❌ build: <crate> — <first error[Exxxx] line>
❌ deploy: /health timeout after 5s · journal tail: <last line>
❌ deploy --roll: dream-cycle lock held, aborted (retry in <age>s)
❌ push: pre-push gate failed — <hook-name> · binary already live locally
```

## Invariants

- **Never `git reset --hard`** to recover — if cut-release committed but push failed, the commit stays; user re-pushes manually.
- **Never `--no-verify`** on push — if the pre-push gate is blocking a legitimate fix, user must add `--skip-precheck` explicitly.
- **Always `fuser -k`** before `cp` — the "Text file busy" error is deterministic and fuser is the standard fix.
- **Always report the binary version** — `/health` is unreliable post-0.4.1→0.5.0 bug where the version string was hardcoded.

## Example Invocations (what the user prompts you with)

- `deploy` — minimal
- `deploy --push` — ship it
- `deploy --release patch --push` — full release flow
- `deploy --roll --push` — zero-downtime swap + push
- `deploy --skip-precheck --allow-dirty` — rapid iteration (skip safety nets)
