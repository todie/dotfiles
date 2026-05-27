---
name: deploy-status
description: Three-way version check across on-disk binary (`reveried --version` or `engram --version`), running daemon (`/health` on port 7437), and git main (`git rev-parse origin/main` + `Cargo.toml` workspace version). Surfaces "needs restart" (disk ≠ running) vs "needs `make install`" (workspace ≠ disk) vs "in sync" with a single-line verdict + a grid of the four facts. Use when the user says "what version is running", "is the daemon up to date", "deploy status", "am I on the latest", or before cutting a release. Args — none required, optional `--json` for machine-readable output.
---

# deploy-status — three-way version reconciliation for reveried

Answer "is what I'm running actually what's on disk, and is what's on disk actually what's on main?" in one shot. The reverie daemon has four independent version truths — workspace Cargo.toml, installed binary, in-memory running daemon, git HEAD — and they drift. This skill aligns them and tells you which step (`make install` or daemon restart) is missing.

## When to use

- User says "what version is running", "deploy status", "is reveried up to date", "am I on main"
- Before cutting a release (`/cut-release`) to confirm the baseline
- After a `make install` to confirm the running daemon actually restarted to pick it up
- When `/health` returns a version that doesn't match the commit you just pushed

## When NOT to use

- You want to change versions — use `/cut-release` (bump + tag) or `/reveried-swap` (install + hot-swap).
- You want the full health payload — `curl -sf http://127.0.0.1:7437/health | jq .` directly.
- You want to check remote deploys (Vercel, Helm) — this skill is local-only.

## Procedure

### 1. Parse args / preconditions

- `--json`: emit machine-readable JSON instead of the human grid. Default: off.

No preconditions — skill is read-only and degrades gracefully.

### 2. Gather the four facts

Run all four in parallel where possible. Each independently degrades to `unknown` on failure — the skill's value is in reconciling whatever facts are available.

**a) On-disk binary version.** Binary name drifts between `reveried` and `engram`; try both:

```bash
DISK_VERSION=$(~/.local/bin/reveried --version 2>/dev/null \
              || ~/.local/bin/engram --version 2>/dev/null \
              || echo "unknown")
DISK_VERSION=$(echo "$DISK_VERSION" | awk '{print $NF}')  # strip "reveried "/"engram " prefix
```

**b) Running daemon version.**

```bash
RUNNING_JSON=$(curl -sf --max-time 3 http://127.0.0.1:7437/health 2>/dev/null)
if [ -n "$RUNNING_JSON" ]; then
  RUNNING_VERSION=$(echo "$RUNNING_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","unknown"))')
else
  RUNNING_VERSION="unreachable"
fi
```

**c) Git main SHA.**

```bash
MAIN_SHA=$(git -C ~/projects/reverie rev-parse --short=7 origin/main 2>/dev/null || echo "unknown")
HEAD_SHA=$(git -C ~/projects/reverie rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
BEHIND=$(git -C ~/projects/reverie rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
AHEAD=$(git -C ~/projects/reverie rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
```

**d) Workspace version.** Parse `Cargo.toml` at the repo root:

```bash
WORKSPACE_VERSION=$(python3 -c '
import re
with open("/home/ctodie/projects/reverie/Cargo.toml") as f:
    for line in f:
        m = re.match(r"^version\s*=\s*\"([^\"]+)\"", line)
        if m:
            print(m.group(1))
            break
' 2>/dev/null || echo "unknown")
```

(If the workspace uses `[workspace.package]` with `version =`, that's the one to read; the skill should find it in the first 40 lines.)

### 3. Reconcile

Two primary comparisons:

- **disk vs running**: if different (and running is not `unreachable`) → "needs restart" (run `/reveried-swap` or restart the daemon).
- **workspace vs disk**: if different → "needs `make install`".
- **HEAD vs origin/main**: if BEHIND > 0 → "branch is behind origin/main by N commits"; if AHEAD > 0 → note "branch ahead by M commits (unpushed)".

Additional:
- If running == `unreachable`: verdict is "daemon down".
- If all four align and BEHIND == 0: verdict is "in sync".

### 4. Report

Default (human grid):

```
deploy-status:
  workspace (Cargo.toml):  0.6.1
  on-disk   (~/.local/bin): 0.6.1
  running   (/health):      0.6.0
  git HEAD:                 065eb98
  git origin/main:          065eb98 (ahead 0, behind 0)

verdict: needs restart (on-disk 0.6.1 but running 0.6.0 — run `/reveried-swap` or restart reveried)
```

With `--json`:

```json
{
  "workspace": "0.6.1",
  "on_disk": "0.6.1",
  "running": "0.6.0",
  "head_sha": "065eb98",
  "main_sha": "065eb98",
  "ahead": 0,
  "behind": 0,
  "verdict": "needs_restart",
  "action": "reveried-swap"
}
```

Verdict enum: `in_sync`, `needs_restart`, `needs_install`, `needs_install_and_restart`, `behind_main`, `daemon_down`, `unknown`.

## Examples

```
/deploy-status
```

Human-readable grid + one-line verdict.

```
/deploy-status --json
```

Machine-readable output — pipe into `jq` or use in a script.

## Safety invariants

- Read-only — never touches disk, daemon, or git state.
- Always degrades gracefully — each of the four facts is independent; a missing one reports `unknown` rather than aborting.
- Never assumes binary name — tries both `reveried` and `engram`.
- Never calls `/reveried-swap` or `make install` itself — this skill reports, the user (or another skill) acts.

## Related skills

- `/reveried-swap` — rebuilds + hot-swaps the daemon binary (the action when this skill says "needs restart").
- `/cut-release` — bumps the workspace version + tags (precedes "needs install" fixes).
- `/ci-lint` — pre-commit/pre-push lint sweep (separate concern).
