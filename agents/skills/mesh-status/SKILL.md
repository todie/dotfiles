---
name: mesh-status
description: Show health and topology of the reverie agent mesh — coord peers, locks, daemons, log fanout, llm-offload, recent assignments. Use when the user asks "what's the mesh doing", "who's alive", "show me the workers", "is the mesh healthy", or wants a quick at-a-glance dashboard before dispatching new work. Subcommands let you scope to peers/locks/daemons/logs/traffic/watch.
---

# mesh-status

Single command to surface the reverie mesh's live state. Built for the anchor session (or any peer) to answer "is everything alive" without spelunking through `coord peers`, `docker ps`, `redis-cli`, `tmux ls`, and a half-dozen log files.

## User story

> As the **anchor of the reverie mesh**, I want a one-command summary of every moving part in the mesh — workers, locks, daemons, log fanout, LLM offload, recent coord traffic — so that **before I dispatch new work I can see at a glance whether the mesh is healthy and which lanes are free**, and **so that when something breaks I can pinpoint the failed lane in under five seconds**.

> As an **on-call human checking on the mesh from a fresh terminal**, I want to run `/mesh-status` and immediately see a green/yellow/red signal with a one-line reason per failure, so I can decide whether to escalate, restart, or ignore.

> As a **worker peer (e.g. control-room) auditing my own dependencies**, I want `/mesh-status daemons` to show every daemon I'm responsible for plus its last health check, so I can detect drift between my mental model and reality.

## Features

### Core
- **Peers** — live coord peers from `~/.claude/bin/coord peers --live`, grouped by role, with last heartbeat age
- **Locks** — held shared-state locks (main-branch, pr-merge-queue, engram-serve, cargo-build, batch-dispatch) with owner + reason + age
- **Daemons** — liveness probes for: reveried (`:7438/health`), engram-legacy (`:7437/health`), redis (`PING`), memcached (`stats`), ollama (`/api/tags`), llama-server (`:8080/health` if present), gate (`:7440/health` if present)
- **Log fanout** — `redis-cli pubsub channels 'logs.*'` count + `xlen` of `logs:stream:*` per service. Flag if zero (no producers wired up yet).
- **LLM offload** — quick health probe of ollama + last 1 hour of offload telemetry from engram (count, escalation rate, avg duration)
- **Traffic** — last 10 coord messages from any peer's inbox (subject + sender + age)
- **Tmux topology** — list of tmux sessions matching `reverie-*` and the main window's pane layout
- **Health summary** — single `OK / DEGRADED / DOWN` line with the worst-failing component cited

### Output modes
- **default** — full multi-section dump (~80 lines)
- **--brief** — one-line summary (the health line + peer count + 1 sentence)
- **--json** — machine-readable for piping to dashboards or other tools
- **--watch[=Ns]** — repeated polling, default 5s, clears between iterations
- **--since <duration>** — restrict traffic + offload telemetry to a window

### Filters
- **--role <role>** — only show one peer's row + their owned daemons + their inbox
- **--component <peers|locks|daemons|logs|offload|traffic|tmux>** — only one section
- **--no-color** — strip ANSI for piping to file

## CLI subcommands

The skill is invoked via `/mesh-status [args]`. Subcommands map to the Features sections above:

```
/mesh-status                    # full dump
/mesh-status peers              # just peers
/mesh-status locks              # just locks
/mesh-status daemons            # just daemons
/mesh-status logs               # log fanout state
/mesh-status offload            # llm-offload health + last hour stats
/mesh-status traffic [N]        # last N coord messages (default 10)
/mesh-status tmux               # tmux topology only
/mesh-status health             # one-line summary (good for shell prompt integration)
/mesh-status watch [Ns]         # repeated polling, default 5s
/mesh-status --json             # machine-readable
/mesh-status --role archive     # scope to one role's view
/mesh-status --since 1h         # window for traffic + offload
/mesh-status diff               # diff against the last snapshot saved to engram
/mesh-status snapshot           # save current state to engram under coord/mesh-snapshot/<ts>
```

### Exit codes
- 0 — OK (all components green)
- 1 — DEGRADED (one or more components yellow but mesh still functional)
- 2 — DOWN (a critical component — coord, redis, or anchor itself — is unreachable)
- 3 — usage error

Exit codes let you wire `/mesh-status health` into shell prompts, cron checks, and CI gates.

## Implementation outline

The skill is a bash script at `~/.agents/skills/mesh-status/run.sh` (invoked by the slash-command runner). It is **read-only** — never writes to coord, never restarts daemons, never edits engram (except `snapshot`).

```bash
#!/usr/bin/env bash
set -euo pipefail
sub="${1:-default}"
case "$sub" in
  peers)    show_peers ;;
  locks)    show_locks ;;
  daemons)  show_daemons ;;
  logs)     show_logs ;;
  offload)  show_offload ;;
  traffic)  show_traffic "${2:-10}" ;;
  tmux)     show_tmux ;;
  health)   show_health_summary; exit $? ;;
  watch)    while true; do clear; show_full; sleep "${2:-5}"; done ;;
  snapshot) write_snapshot_to_engram ;;
  diff)     diff_against_last_snapshot ;;
  --json)   show_full --format=json ;;
  default|"") show_full ;;
  *) echo "usage: /mesh-status [peers|locks|daemons|logs|offload|traffic|tmux|health|watch|snapshot|diff|--json] [args]" >&2; exit 3 ;;
esac
```

Each `show_*` function calls a single tool and pretty-prints. No retries — if redis is down, the redis section just says `DOWN`.

## E2E tests

The skill ships with `tests/e2e.sh` exercising every subcommand against a live mesh. Tests are designed to be run from the anchor session.

```bash
#!/usr/bin/env bash
# tests/e2e.sh — run from anchor session, requires a live mesh
set -euo pipefail
SKILL=/home/ctodie/.agents/skills/mesh-status/run.sh
pass=0; fail=0
assert() { if eval "$2"; then pass=$((pass+1)); echo "ok  - $1"; else fail=$((fail+1)); echo "FAIL- $1"; fi }

# 1. default returns 0 when mesh healthy
$SKILL > /tmp/ms.out 2>&1
assert "default exit 0" '[ $? -eq 0 ]'
assert "default mentions peers"   'grep -q "peers"   /tmp/ms.out'
assert "default mentions daemons" 'grep -q "daemons" /tmp/ms.out'
assert "default mentions locks"   'grep -q "locks"   /tmp/ms.out'

# 2. peers subcommand only shows the peers section
$SKILL peers > /tmp/ms-peers.out
assert "peers section only" '[ $(grep -c "===" /tmp/ms-peers.out) -le 1 ]'
assert "peers includes anchor"   'grep -q anchor       /tmp/ms-peers.out'
assert "peers includes archive"  'grep -q archive      /tmp/ms-peers.out'
assert "peers includes editor"   'grep -q editor       /tmp/ms-peers.out'
assert "peers includes control-room" 'grep -q control-room /tmp/ms-peers.out'

# 3. daemons probes redis, memcached, ollama
$SKILL daemons > /tmp/ms-d.out
assert "redis row"     'grep -qE "redis.*OK"     /tmp/ms-d.out'
assert "memcached row" 'grep -qE "memcached.*OK" /tmp/ms-d.out'
assert "ollama row"    'grep -qE "ollama.*OK"    /tmp/ms-d.out'

# 4. health subcommand exit code reflects state
$SKILL health; rc=$?
assert "health exit code in {0,1,2}" '[ $rc -ge 0 ] && [ $rc -le 2 ]'

# 5. --json output is parseable
$SKILL --json | python3 -c 'import json,sys;json.load(sys.stdin)'
assert "--json parses" '[ $? -eq 0 ]'

# 6. --role filters output
$SKILL --role archive > /tmp/ms-role.out
assert "--role archive shows archive" 'grep -q archive /tmp/ms-role.out'
assert "--role archive hides editor"  '! grep -q "role=editor" /tmp/ms-role.out'

# 7. snapshot writes to engram
$SKILL snapshot > /tmp/ms-snap.out
assert "snapshot reports obs id" 'grep -qE "obs #[0-9]+" /tmp/ms-snap.out'

# 8. diff against last snapshot
$SKILL diff > /tmp/ms-diff.out
assert "diff exits 0 or 1" '[ $? -le 1 ]'

# 9. failure injection — kill a peer, expect DEGRADED
victim=$(coord peers --live | python3 -c 'import json,sys;p=json.load(sys.stdin);print(next(x["claude_pid"] for x in p if x.get("role")=="scout"))')
kill -STOP $victim
sleep 7  # heartbeat ages out
$SKILL health; rc=$?
assert "health DEGRADED when peer stale" '[ $rc -eq 1 ]'
kill -CONT $victim

# 10. failure injection — stop redis, expect DOWN
docker stop reverie-redis >/dev/null
sleep 2
$SKILL health; rc=$?
assert "health DOWN when redis dead" '[ $rc -eq 2 ]'
docker start reverie-redis >/dev/null

# 11. --component filter
$SKILL --component daemons > /tmp/ms-c.out
assert "--component daemons hides peers" '! grep -q "=== peers" /tmp/ms-c.out'

# 12. traffic shows recent messages
coord send "$(coord peers --live | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['session_id'])")" assignment ping --body '{}' >/dev/null
sleep 1
$SKILL traffic 5 > /tmp/ms-t.out
assert "traffic includes ping" 'grep -q ping /tmp/ms-t.out'

echo "---"
echo "passed: $pass    failed: $fail"
exit $fail
```

### Test categories
- **smoke** — every subcommand returns 0 on a healthy mesh (tests 1-4)
- **format** — `--json` parses, `--brief` is one line, `--no-color` strips ANSI (tests 5)
- **filtering** — `--role`, `--component` produce correctly scoped output (tests 6, 11)
- **persistence** — `snapshot` writes to engram, `diff` reads it back (tests 7, 8)
- **failure injection** — degraded peer + dead redis trigger correct exit codes (tests 9, 10)
- **traffic** — coord send is visible in next `/mesh-status traffic` call (test 12)

## Caveats

- Read-only by design. Never restarts a daemon, never re-registers a peer, never sends coord messages (except `snapshot`).
- Polling cadence in `watch` is dumb — no exponential backoff. If you want to drive a dashboard, use `--json` and your own scheduler.
- Tmux pane layout output assumes the anchor's tmux server. Won't see other tmux servers if any.
- Log fanout section will report 0 messages until the protocol/redis-log-fanout producers exist. That's expected pre-Phase-1.

## Cross-references
- coord protocol: `~/projects/reverie/docs/coord/protocol-v0.md`
- engram topic_keys: `role/mesh/topology`, `role/anchor`, `protocol/redis-log-fanout`, `infra/gate-relay-docker`, `policy/offload-to-llm`
- related skills: `coord-drain` (drain inbox), `complain-to-the-wizard` (escalate to wizard role), `herald-audit` (deeper situational audit)
