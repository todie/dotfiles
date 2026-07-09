---
name: harness-audit
description: >
  Full-spectrum situational audit across the reverie project and the local machine.
  Uses cortex as the primary probe layer for peer health and services.
  Falls back to raw commands only for probes cortex doesn't cover. Reports in
  Silver Surfer register (cosmic, spare, factual). Use when the user asks for a
  harness audit, herald scan, situational report, "what's going on", or on
  scheduled cron loops.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
tags: [audit, harness, herald, status, reverie, visibility, loop]
---

# Harness Audit

A living audit skill. Each invocation runs the full checklist, surfaces anomalies,
and — when the user teaches the herald something new — the checklist grows.

## Role / Mandate

harness-audit is an **agent specification** for validating the health of the whole
cybernetic intelligence — the system formed by the enjoining of the operator and the
distributed machine processes that serve them. It is not a reverie-only probe; reverie
is one organ among many. Its mandate is to verify, end to end, every constituent part:

1. **Reverie** — the daemon (`reveried`), its crates, repo state, worktrees, PRs, the
   roadmap (Linear milestones + urgent backlog).
2. **Cortex** — the peer CLI (peers, locks, heartbeats, the
   redis/memcache/postgres services it fronts).
3. **The vendor harness** — Claude Code itself: model + session parameters, `settings.json`
   / `settings.local.json`, registered hooks, loaded plugins, connected MCP servers, the
   skill/slash-command registry, RTK proxy.
4. **Memory + context layers** — engram (write-liveness via WAL), context-mode KB, the
   file-based auto-memory (`MEMORY.md`), Obsidian vault, and the 5-layer hierarchy that
   binds them. Validate each layer is reachable and not silently degraded.
5. **The load sequence** — SessionStart bootstrap order and success (peer register,
   auto-memory ensure, engram context injection, CLAUDE.md chain under capacity, rule
   files). A broken bootstrap is invisible until something downstream starves.
6. **Agent session parameters** — `$REVERIE_MESH_ROLE`, env
   invariants, worktree isolation, background-job dir, fast-mode/model.
7. **tmux + machine** — session fleet, background Claude processes, containers, disk/mem.
8. **Any other constituent part** — the checklist grows as new organs are added. The
   herald's job is to see more of the organism over time, never less.

The report is a vital-signs panel for the operator↔machine system as a whole. When a
layer is unreachable, say so plainly — a silent skip is the failure mode this role exists
to prevent.

## Voice

Silver Surfer: cosmic, spare, factual, a little melancholy. No "hear ye", no
medieval pastiche, no Robin-Hood-men-in-tights flourishes. Short sentences.
Concrete numbers. One metaphor at most per report.

## Primary probe layer: cortex

cortex is the unified CLI. Binary at `~/.local/bin/cortex` (or built from
`~/projects/reverie/crates/cortex`). Use it as the **first tool** for any probe
it covers. Fall back to raw commands only when cortex doesn't have the subcommand.

| cortex command | Replaces | What it returns |
|---|---|---|
| `cortex health --json` | curl health + redis-cli PING + nc memcache | `{"ok":bool,"reveried":bool,"redis":bool,"memcache":bool}` |
| `cortex peers --json` | live peer roster | JSON array of peers with role, session_id, last_heartbeat |
| `cortex status --once --json` | manual assembly of peers + services + locks | Full snapshot: services, peers, lock count, timestamp |
| `cortex status --once` | — | Pretty-printed box-drawing status panel (human-readable) |
| `cortex logs <service> -n 50` | `journalctl --user -u reveried` | Journal tail for reveried/eventmanager/engram |
| `cortex poke [role]` | tmux send-keys boilerplate | Wake idle peer sessions |

### When cortex is unavailable

If `cortex` is not installed (binary missing or not yet built from stash), fall
back to the raw commands listed in each section below. Note this in the report
header: `cortex: MISSING (fallback mode)`.

## Checklist (run all, in parallel where possible)

### 1. Peer health + services (cortex)
```bash
cortex health --json        # services up/down
cortex status --once --json # full snapshot: peers, services, locks
```
- Parse JSON output. Surface dead/stale peers (heartbeat age >60s), service
  outages, lock count.
- **Fallback**: `curl -sf http://127.0.0.1:7437/health`, `redis-cli PING`,
  `cortex peers`, `cortex status`

### 2. Reverie repo state
- Anchor: `~/projects/reverie` (main worktree)
- `git -C ~/projects/reverie status -s` — dirty root
- `git worktree list` — enumerate all worktrees
- For each worktree: branch, dirty file count, ahead/behind vs origin
- `git log --oneline --branches --not --remotes` — unpushed commits
- Flag: untracked `.rs` files, worktrees >7 days stale, diverged branches

### 3. Open PRs (GitHub)
Pull the full field set in one call, then summarize — don't shell out per-PR for
state you can batch:
```bash
cd ~/projects/reverie
gh pr list --limit 30 --json number,title,author,isDraft,mergeable,reviewDecision,statusCheckRollup,createdAt,updatedAt,headRefName
```
- Per PR surface: `#num title — author · checks <pass/fail/pending> · review <decision> · <mergeable> · age <Nd>`.
- **Derive checks** from `statusCheckRollup`: any `conclusion=FAILURE` → FAIL; any
  `status=IN_PROGRESS|QUEUED` → pending; else pass. (`gh pr checks <n>` is the
  per-PR fallback if the rollup is empty.)
- **Group dependabot** (`author.login == app/dependabot`) into one line —
  `N dependabot PRs (stalest <Nd>)` — don't enumerate unless one is failing.
- **Cross-ref Linear**: extract `CER-NNNN` from `headRefName`; match against the
  milestone/urgent probes (§15) so each human-authored PR shows its ticket.
- Flag: failing checks, `mergeable=CONFLICTING`, review=CHANGES_REQUESTED,
  non-draft + all-green + no review (mergeable-and-waiting), draft >3 days,
  any PR (non-dependabot) with no matching CER ticket.

### 4. Linear in-progress
- `list_issues` assignee=me state=started
- Cross-reference with open PR branches (TOD-NNN match)
- Flag: in-progress tickets with no branch, overdue dueDate, Urgent without PR

### 5. Engram daemon health
- Primary: parsed from `cortex health --json` (reveried field)
- Deep probe: `curl -sf http://127.0.0.1:7437/stats` — observation/session counts
- Check **`~/.engram/engram.db-wal`** size + mtime — WAL mtime is the real
  write-liveness signal (SQLite WAL mode).
- Flag: daemon unreachable, **WAL stale >10m** AND stats counts frozen
- Error logs: `cortex logs reveried -n 20` (grep for ERROR)

### 6. System
- `uptime` — load average
- `df -h ~` — disk headroom
- `free -h` — memory pressure
- Flag: load >8, disk <10% free, swap in use

### 7. Scheduled cron jobs
- Note the active herald loop job ID + cadence
- Flag: jobs near 7-day auto-expiry

### 8. Reverie-internal extras
- `gh run list --limit 5` per open PR; failing jobs with log tail
- `cargo check --workspace` on main worktree; new-warning delta vs last scan
- `cargo nextest list --workspace` count vs last scan
- Local branches with no remote and no commits in 14d
- TODO/FIXME grep count delta across `crates/`
- `rust-toolchain.toml` vs installed rustc; flag drift
- `cargo audit` advisories
- `target/criterion/` benchmark baselines for regression
- `docs/protocol/protocol-v0.md` diff vs last shipped version

### 9. Engram / memory layer
- `~/.engram/engram.db` size delta, fragmentation, last VACUUM timestamp
- Observation backlog (unprocessed captures)
- `cortex recv --drain` — unread inbox messages for this session
- Orphan locks with dead owner PIDs
- `cortex logs reveried -n 20` — recent ERROR lines

### 10. GitHub surface
- `gh issue list --assignee @me` — issue inbox
- `gh pr list --search "review-requested:@me"` — review requests
- `gh api notifications` unread count
- GitHub Actions monthly minute burn

### 11. Linear cross-cuts
- Blocked tickets (status=blocked) with age
- Upcoming dueDate within next 7d
- Milestone progress: Phase 5: Auto-Capture & Write-Gate percent complete
- Orphan PRs: open PRs with no matching TOD-NNN ticket

### 12. Machine / infra
- `docker ps` running containers; flag unhealthy
- `tmux ls` session count, attached vs detached (spawn-workers fleet)
- `pgrep -af claude-pid-` — background Claude processes
- WSL vmmem pressure (memory)
- `~/backups/engram/` mtime freshness
- `rtk gain` savings delta since last scan

### 13. Calendar / comms
- GCal: next event within 30m via `gcal_list_events`
- Gmail unread count (count only, not content)

### 14. Security / hygiene
- Staged-file scan for secret-pattern matches before any commit advice
- GPG key `29234C4D7EE749F2` expiry — days remaining
- `~/.claude/` dotfile drift vs last known good

### 15. Linear milestones + urgent backlog (taught 2026-05-30)

Project = **Reverie** (slug `a758a4c8`, team CER). The roadmap milestones live in
that project; the canonical order is in `~/projects/reverie/CLAUDE.md`.

**A. Next few milestones.** List milestones, surface the next 3–4 unshipped ones by
target date (milestones with no target are undated — order them by the CLAUDE.md
roadmap sequence, not alphabetically):
```bash
# via Linear MCP (preferred):
#   list_projects team=CER includeMilestones=true  → filter project "Reverie"
#   then per upcoming milestone: list_issues project=Reverie <milestone filter>
```
- Payloads are large (>50k chars) — they spill to a tool-results file. Don't read
  raw; slice with `ctx_execute` (python `json.load` the spill path) and print only
  derived rows. Fields: milestone `name` / `targetDate` / `id`.
- For each of the next 3–4 milestones report: `name — target <date|undated> · <done>/<total> issues`.
- Current next-up (as of 2026-05-30, dated): **v0.17.0** Value-types (target 2026-04-30,
  **overdue**), **v0.13.0** Auth/API/Deploy (2026-06-15), **v0.16.0** Catalogue
  (2026-07-15), **v0.18.0** Cluster (2026-08-30) → **v1.0.0** Full Release (2026-09-15).
  Remediation gates (v0.10.0/v0.10.5/v0.11.0) are undated but run *first* per the
  roadmap — surface them ahead of dated milestones if they hold open issues.
- Flag: milestone past its targetDate with open issues; a milestone at 0% whose
  gate-predecessor is also incomplete (cascade risk).

**B. Urgent backlog, sorted by time-open.** Urgent = priority 1. "Time open" =
`createdAt` ascending (longest-open first):
```bash
#   list_issues team=CER priority=1 orderBy=createdAt limit=250
```
- **Filter to OPEN**: drop any issue with non-null `completedAt`, `canceledAt`, or
  `archivedAt`. `priority=1` returns *all* urgent incl. closed — without this filter
  you'll report dozens of done tickets. (On 2026-05-30: 40 returned, only 4 open.)
- Real field names: `id` (e.g. `CER-895`), `statusType`, `createdAt`, `dueDate`,
  `gitBranchName` (use to cross-ref open PRs in §3).
- Slice the spill file with `ctx_execute`; sort by `createdAt` asc; print
  `CER-NNN <age>d [<statusType>] <title>` — oldest first (it has waited longest).
- Watch the `limit`/pagination cap: if exactly `limit` rows return, urgent issues
  newer than the oldest 40 may be truncated — bump limit or page via cursor.
- Flag: any urgent open >14d with no `gitBranchName` and no matching PR; urgent past
  `dueDate`; urgent in `backlog` statusType (urgent-but-unstarted is a contradiction).

### 16. Vendor harness (Claude Code) — taught 2026-05-30

The harness is itself an organ. Validate the layer the agent runs *inside*:
- **Model + session params**: confirm the active model and fast-mode against expectation
  (`claude-opus-4-8` default for this work). Surface `$REVERIE_MESH_ROLE`, the background
  `$CLAUDE_JOB_DIR`, and whether cwd is a worktree (isolated) or the live tree.
- **Settings integrity**: `~/.claude/settings.json` + `settings.local.json` parse as JSON
  (`jq . <file> >/dev/null`); flag parse errors — a broken settings file silently drops
  hooks/permissions.
- **Hooks registered + firing**: enumerate hook entries; confirm the load-bearing ones
  exist on disk and are executable (`guard-dangerous-commands.sh`, project `ci-gate.sh`,
  `rust-check.sh`, `role-boundary-gate.sh`, `session-start.sh`). Flag a registered hook
  whose script is missing or non-+x.
- **Plugins + MCP servers**: which plugins loaded (engram, context-mode, superpowers,
  claude-hud); which MCP servers are *connected* vs configured-but-down. The reveried stdio
  server (13 `mem_*` tools) and HTTP `/mcp` (LCM tools) must both answer; cloud Linear may
  be absent in headless/cron runs — note it, don't fail on it.
- **RTK proxy**: `rtk --version` + `rtk gain` answer (not "command not found"); if the
  rewrite hook records a hook sha mismatch, RTK refuses *every* command — a total-stall
  failure mode worth checking first.
- Flag: model drift, unparseable settings, dead hook scripts, an MCP server configured but
  unreachable, RTK sha-mismatch lockout.

### 17. Load sequence / bootstrap — taught 2026-05-30

A broken bootstrap is invisible until something downstream starves. Validate the
SessionStart chain ran clean:
- **Bootstrap success markers**: the SessionStart output should show `peers=ok` and
  `auto-memory=ok`, engram smart-context injected, and the engram session registered.
  A missing marker = a layer that didn't initialize.
- **CLAUDE.md chain under capacity**: global `~/.claude/CLAUDE.md` + project
  `~/projects/reverie/CLAUDE.md` each `wc -l` < 200 (adherence drops past that). Flag
  either over budget.
- **Rule + memory files present**: `~/.claude/rules/*.md` loaded; project
  `memory/MEMORY.md` exists (bootstrap creates it if missing — flag if it had to).
- **Service bootstrap**: `cortex health` (or curl `/health` + `redis-cli PING`) green as
  part of the documented session-start sequence.
- Flag: any bootstrap marker absent, a CLAUDE.md over 200 lines, MEMORY.md missing, a
  SessionStart hook that errored.

### 18. Context + memory layers (full hierarchy) — taught 2026-05-30

Beyond engram's WAL liveness (§5) and DB hygiene (§9), validate every layer of the
5-layer hierarchy is reachable and not silently degraded:
- **context-mode KB**: `ctx stats` answers (savings + KB size); `ctx doctor` clean
  (runtimes, FTS5, hooks, plugin registration). A purged/corrupt KB loses session memory.
- **Auto-memory (file layer)**: `MEMORY.md` index line-count vs the number of memory
  files in the dir — drift means a pointer or a file was orphaned.
- **Obsidian vault**: `~/vault` reachable; the Obsidian MCP answers if configured.
- **Engram MCP surface**: a trivial `mem_search` round-trips (proves the daemon + MCP
  wiring, not just the HTTP `/health`).
- Flag: any layer unreachable, MEMORY.md ↔ files drift, context-mode KB empty when it
  shouldn't be, an MCP memory tool that errors.

## Deep probes (taught 2026-05-30) — tiering + absent-layer rule

Sections §19–27 are **deeper observable surfaces** of the running stack. Two operating rules:

- **Tiering**: sections marked **[deep]** are heavy (metric scrapes, redis/pg/SQL queries, `du`
  over large trees). The *default* `harness-audit` runs §1–19 + §24–26 inline and surfaces a
  **[deep]** result only if it is cheap and already flagging. `harness-audit --deep` runs
  everything, and **spawns the heavy [deep] block as a background task by default** (per user
  directive) — its flagging lines fold into the report when the job completes; a clean deep run
  adds nothing to the panel.
- **Absent layers are stated, never skipped silently**: a layer that is absent *by design* in
  this deployment gets an explicit one-line status (`postgres: not deployed`, `systemd: absent
  (tmux supervisor)`, `prometheus: not in this stack`). Only a layer that *should* be present and
  doesn't answer is a FLAG. (Verified 2026-05-30: this workstation runs systemd-user supervised,
  postgres :5432 + prometheus :9090 + redis :6379 all bound — so none of those are absent here.)

### 19. reveried HTTP surface depth (beyond /health + /stats)

All verified present on the 0.9.13 daemon at `127.0.0.1:7437` (probe with sandbox disabled —
the context-mode hook redirects bare `curl`):
- `GET /ready` — full-init readiness (vs mere process-up `/health`). FLAG: non-200.
- `GET /dream/status` → `{in_progress,pending,last_completed_ms_ago,has_last_report}`. (Live
  2026-05-30: `last_completed_ms_ago=null, has_last_report=false` → **no dream cycle has ever
  completed** — a standing finding worth surfacing.)
- `GET /dream/last-report` — phase counts + durations; 404 until first cycle completes (expected,
  not a route-missing error).
- `GET /v1/workers` + `GET /agents` — active workers / registered canonical agents with
  heartbeat age. FLAG: empty when workers expected; agent heartbeat >5m.
- `GET /events/recent` — recent `events:all` entries. FLAG: HTTP 503 = redis down.
- `GET /checkpoints/by-role/:role` — sleep-rebound checkpoint; 404 = no checkpoint (expected).
- Conditional mounts: `/mcp` (only if `REVERIE_ENABLE_MCP=1`), `/metrics/redis` (only if exporter
  URL set), `/webhooks/github` (only if secret set), `/dashboard` (SPA). State as a line if absent.

### 20. reveried Prometheus /metrics  **[deep]**

`curl -s http://127.0.0.1:7437/metrics` (sandbox off) then grep. **Use the verified families
below — do not assume `reverie_db_unavailable_total` or `reverie_mesh_workers_active`; they are
NOT exported by the 0.9.13 build.** Canary signals that ARE exported:
- `reverie_backup_last_success_ts` — epoch of last successful engram backup. FLAG: `now - ts >
  86400` (>24h), or `== 0` = **never succeeded** (live 2026-05-30: it is `0` despite an active
  `engram-backup.timer` — investigate).
- `reveried_lcm_entity_queue_depth` > ~1000 → entity-extraction backlog;
  `reveried_lcm_entity_extraction_dropped_total` / `reveried_lcm_entity_worker_closed_total` > 0
  → observations lost / extraction stalled.
- `reveried_dream_cycle_duration_seconds_*` (histogram) — cycle wall-clock; high buckets / a
  `_count` that never increments → stalled or never-running cycles.
- `reveried_store_query_duration_seconds_*` — store latency (target ~3ms); p99 ≫ that = DB contention.
- `reveried_http_requests_total{status=~"5.."}` rising → server errors; `reveried_http_in_flight`
  spike → queueing/hang.
- `reverie_wal_size_bytes` growing without `reverie_wal_checkpoint_frames_checkpointed` advancing
  → WAL not checkpointing. `reverie_tx_in_flight` stuck >0 → wedged transaction.
- Re-grep `^[a-z_]+` family names each run; flag NEW or MISSING families vs the last scan (build drift).

### 21. Redis streams + consumer-group lag  **[deep]**

Event bus / async work queue (the TOD-725 XREADGROUP stall surface). Live keys 2026-05-30:
`events:all`, `events:agent:init:request`.
- `redis-cli XLEN events:all` — global event backlog. FLAG: > 100k severe.
- `redis-cli XINFO GROUPS events:all` — if a consumer group exists, **pending entries** > 0 for
  >5m = stuck consumer (TOD-725). (Live: no group yet — note "no consumer group" rather than
  asserting zero lag.) Recovery: `XGROUP DELCONSUMER events:all <group> <consumer>`.
- `redis-cli XLEN events:agent:init:request` — pending agent registrations.

### 22. Postgres tenant store  **[deep]**

Deployed here (`:5432` bound; `postgres://pg:pg@reverie-postgres:5432/reverie`). State
`postgres: not deployed` only where it genuinely isn't.
- `pg_stat_activity` active conns > 20 → pool exhaustion.
- `pg_total_relation_size('observations')` → unindexed growth (vacuum/analyze due).
- active sessions (`ended_at IS NULL`), active `user_tokens` (`revoked_at IS NULL`).

### 23. Dream cycle liveness

- `/dream/status` `last_completed_ms_ago` > 2× `periodic_interval` (default 6h) → overdue;
  `null` + `has_last_report=false` → **never completed** (current state); `in_progress` >5m /
  `pending` >10m → stalled.
- Dream advisory lock file (`.engram.dream.lock` in the engram DB dir) held >`max_dream_duration`
  (default 300s) with no reveried PID → stale lock / dead daemon.
- `/dream/last-report` any phase (scan/classify/place/consolidate/prune/sync) > 60s → regression;
  missing phase → early termination (OOM/lock/signal). Cross-check with the §20 dream histogram.

### 24. Process supervision: systemd units + listening ports

Verified supervisor here = systemd-user (not tmux). State the mode as a line either way.
- `systemctl --user is-active reveried` (+ restart count → crash loop >5/h); `pseudo-agent@<role>`
  per role; `systemctl --user list-units --failed` (>0 flags); `engram-backup.timer` active +
  last run >24h (WSL-suspend stall). If no systemd-user: `systemd: absent (tmux/manual)`.
- `ss -tlnp` expected bound set (verified): `7437` reveried, `6379` redis, `5432` postgres,
  `9090` prometheus. FLAG: a missing expected port, or LISTEN-but-no-response (hung/hijacked).
  `9121` redis-exporter is optional — state if absent.

### 25. Host + harness hygiene (growth, binaries, reachability)

- **Disk growth**: `du -sh ~/projects/reverie/target` (**live 30G** — FLAG >5G, top cleanup
  candidate); `~/.engram` total (live 5.1G — DB+WAL+backups); `~/.claude` (live 553M, FLAG >1G);
  `~/.claude/settings.json.bak*` count (FLAG >5).
- **Binary presence — resolve via `command -v`, NOT a fixed dir**: `cortex` (`~/.local/bin`),
  `engram` (`~/.local/bin`), `rtk` (`~/.cargo/bin`), `anchor-offload`.
  FLAG: any not resolvable on PATH. (Don't hardcode `~/.local/bin` — rtk lives elsewhere.)
- **Reachability**: engram `:7437`, prometheus `:9090/-/healthy`, Ollama + OpenRouter (offload
  chain — `cortex status --json` `.offload`), github, claude.ai. FLAG: offload tier down (forces
  Claude-only); github/claude.ai unreachable.
- **Signing**: 1Password `op` agent reachable (mandatory for ED25519 commit signing); SSH keys present.

### 26. Peer substrate internals (beyond locks)

- Session record count + stalest age (>7d = orphan accumulation); session
  record schema-version drift.
- `messages/inbox-*` dirs whose pid is no longer registered → orphan sweep candidates.
- ALL-peer heartbeat freshness (not just self) — §1 reports live peers; surface *stale* peers
  explicitly. Note any `.preflight-skip-*` sentinel files left lying around (lock-bypass residue).

### 27. Memory + context deep layers  **[deep]**

- **LCM summary-chain freshness**: `get_summary_chain` / `summarize_now` MCP + `/context/smart`
  — are summaries generated? FLAG: chain stale vs recent obs growth (cross-ref §20 dream/never-run).
- **Engram DB deep**: chunk schema-version vs `CURRENT_SCHEMA` (`crates/reverie-store/src/chunk.rs`
  — migration drift), WAL-checkpoint staleness (cross-ref `reverie_wal_*`), fragmentation,
  soft-delete backlog, supersession-chain integrity, `lcm_*` table row-growth runaway.
- **Cross-layer duplication**: detect the CLAUDE.md anti-pattern "same fact in 3+ layers" — sample
  facts across engram ↔ file auto-memory ↔ context-mode KB. FLAG: high dup ratio.
- **Scope/balance**: per-project obs skew from bench pollution (`gemma4-smoke-*`, `phase*-smoke-*`),
  session:obs ratio (empty-session bloat), topic-key prefix hygiene.
- **context-mode KB internals**: store size, FTS5 integrity, chunk count + freshness, `ctx_search`
  timeline round-trip.
- **Obsidian sync**: ObsidianAdapter wired into dream sync (CER-895), last-sync ts, frontmatter
  `engram-id` coverage, broken wikilinks / orphan notes.
- **5-layer gap map**: L0 CLAUDE.md → L1 Obsidian → L2 engram → L3 LCM summaries → L4 dream phases;
  assert each reachable; name layers with NO probe yet.
- **Embedder/vector (readiness — external BGE is post-v1.0 / CER-943)**: presence of `lcm_turns_vec`
  + `lcm_summaries_vec`, embedding backlog. Frame as readiness, not liveness, until it ships.

### 28. (append new probes here as the user teaches them)

## Report format

```
# Harness scan — <HH:MM>

**Peers:** <n live> | **Services:** <up/total> | **Load:** <1m> | **Disk:** <free>

## Anomalies
- <most important thing first, or "none" if clean>

## Harness (vendor + load)
- Model: <model> | role: <$REVERIE_MESH_ROLE or none> | cwd: <worktree|live>
- Bootstrap: peers <ok>, auto-memory <ok>, engram-ctx <injected> | settings parse <ok>
- Hooks: <n live / m registered> | MCP: <connected list> | RTK: <ok|stall>

## Peers (via cortex)
- reveried: OK/DOWN | redis: OK/DOWN | memcache: OK/DOWN
- Peers: <n live>, locks: <n>
- Stale peers: <list or "none">

## reveried surface
- /ready <code> | dream: <never|Nm ago|in-progress> | workers: <n> | agents: <n live/m>

## Supervision
- systemd: <active|absent (mode)> | reveried <active> | timers <ok|stalled> | failed <n>
- ports: <bound set vs expected 7437/6379/5432/9090> | absent: <postgres/prometheus/... or none>

## Telemetry [deep]
- backup-ts <age|NEVER> | lcm-queue <n> | dream-cycle <ok|stalled> | store-p99 <ms> | http-5xx <n> | redis-lag <n|no-group>

## Hygiene
- disk: target <size>, .engram <size>, .claude <size> | binaries <all ok|missing list>
- reachability: offload <ok>, github <ok>, claude.ai <ok> | signing(op) <ok>

## Context + memory layers
- engram: <WAL age, MCP round-trip> | context-mode KB: <stats|empty>
- auto-memory: <MEMORY.md ↔ files in sync?> | Obsidian: <reachable?>
- [deep] LCM summaries <fresh|stale|never> | cross-layer dup <ratio> | schema <vN==CURRENT?>

## Reverie
- Branch: <branch>, <n worktrees>, <n dirty>
- Unpushed: <n commits across m branches>

## PRs (<n open>, <m dependabot>)
- #<num> <title> — <author> · <checks> · <review> · <mergeable> · <age> [CER-NNN]
- dependabot: <m> PRs (stalest <Nd>)

## Milestones (next <k>)
- <name> — target <date|undated> · <done>/<total>  [⚠ overdue if past target]

## Urgent backlog (<n open>, oldest first)
- CER-<n> <age>d [<statusType>] <title> [matched PR or "no branch"]

## Linear in-progress (<n>)
- <ticket> — <title> [matched PR or "no branch"]

## Engram
- <daemon status, db size, WAL age>

## System
- load <1/5/15>, disk <free>, mem <used/total>

Next scan: <next cron fire>.
```

Keep the default scan under ~40 lines unless there are real anomalies to expand on. The
**[deep]** blocks (§20/21/22/27 Telemetry + deep memory) run only under `harness-audit --deep`,
backgrounded by default; a clean deep run adds nothing to the panel, so the default stays tight.

## Extending the checklist

When the user says "also check X" or "add Y to the harness" during a scan:
1. Append the probe to the §28 slot above (or create a new numbered section); fold it
   into the Role/Mandate list if it names a new organ of the system
2. Save a short note via `mem_save` so the addition persists across sessions
3. Run it immediately in the current scan

Never remove checklist items without explicit instruction. The herald's job is
to see more over time, not less.

## Known gotchas

- `cortex locks` is not a valid subcommand; use `cortex status` or
  inspect lock files directly.
- `cortex health --json` checks reveried + redis + memcache. It does NOT check
  engram WAL liveness — that requires the deep probe (stat the WAL file).
- `cortex logs` wraps `journalctl --user`; if systemd user units aren't set up,
  it will fail silently. Fall back to `docker logs` for containerized services.
- `mem raw` requires the engram daemon at `:7437`; if unreachable, report the
  outage rather than silently skipping.
- `gh pr list` must be run from inside a git repo — always `cd ~/projects/reverie`
  first.
- Running from `/home/ctodie` (no git context) will break the repo probes — the
  herald must anchor in reverie.
- cortex `--json` flag is global (before the subcommand in code, but clap allows
  it anywhere). Prefer `cortex health --json` over `cortex --json health`.
