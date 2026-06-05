# Consolidated Claude usage in the tmux glance

**Date:** 2026-06-05
**Status:** Approved design — pending implementation
**Tracking:** Linear (Todie team) — tmux-claude-usage-indicator
**Home:** `todie/dotfiles` (chezmoi-managed)

## Problem

The `tmux-claude-glanced` daemon already renders a multi-session Claude glance in
the tmux status bar — `◉<waiting> ●<active> ⤒<hottest-ctx>%` — plus a per-window
glyph. Everything it shows is derived from **transcripts** (`~/.claude/projects/
*/<session>.jsonl`) and **`/proc/<pid>/environ`** (the pane→session map).

Three pieces of usage data are *structurally invisible* to that pipeline because
they exist **only** in the JSON Claude Code pipes to the statusLine command on
each ~300ms redraw, and are never written to the transcript:

- `cost.total_cost_usd` — cumulative dollar cost of the session
- `rate_limits.five_hour.{used_percentage,resets_at}` — account-global 5h budget
- `rate_limits.seven_day.{used_percentage,resets_at}` — account-global 7d budget
- `cost.total_lines_added` / `cost.total_lines_removed`

claude-hud (the per-pane statusline plugin) consumes these for its own bar, but
that bar is per-pane — there is no consolidated, host-level view of spend or
rate-limit pressure across all the Claude sessions running in the tmux server.

**Goal:** fold the claude-hud usage data into the existing `@claude_glance`
aggregate so one glance answers "how much am I spending right now and how close
am I to a rate limit," consolidated across every live pane — without modifying
the claude-hud plugin (it lives in the plugin cache and is overwritten on every
update) and without adding any shell to tmux's render loop.

## Constraints

- **Plugin untouched.** claude-hud is installed under
  `~/.claude/plugins/cache/claude-hud/claude-hud/<version>/` and is replaced on
  update. Any change there is ephemeral. The integration must be external.
- **stdin is the only source.** `cost` and `rate_limits` are not recoverable from
  the transcript. The statusLine stdin JSON is the sole channel.
- **Zero shell in the tmux render loop.** The status bar must only interpolate
  pre-computed tmux options (the discipline `claude.conf` already enforces — a
  prior `#()` poll once pegged 16 cores). All heavy work stays in the daemon.
- **Server-env knobs.** The daemon runs with the tmux *server's* environment, so
  configuration is via tmux options (`set -g @claude_*`), not shell exports.
- **Cheap per-redraw wrapper.** The wrapper rides claude-hud's existing 300ms
  spawn; it must add at most one `jq` + a throttled background file write, and
  must never delay or corrupt the rendered statusline.

## Architecture

Two components, communicating through a snapshot directory. The plugin and the
tmux render loop are both untouched.

```
                    Claude Code (per pane, ~300ms)
                              │ stdin JSON
                              ▼
            ┌──────────────────────────────────────┐
            │  claude-hud-usage-wrap  (NEW)         │
            │  1. read stdin once                   │
            │  2. pipe verbatim → claude-hud        │──► statusline (unchanged)
            │     (version-resolved), passthrough   │     to Claude Code
            │  3. bg: jq-extract snapshot,          │
            │     atomic write (throttled ~2s)      │
            └──────────────────────────────────────┘
                              │ writes
                              ▼
   ${XDG_RUNTIME_DIR:-/tmp}/claude-hud-usage/<session-uuid>.json
                              ▲
                              │ reads (per live pane)
            ┌──────────────────────────────────────┐
            │  tmux-claude-glanced  (daemon, EXTEND)│
            │  rescan(): also record sid_of[pane]   │
            │  tick():   sum cost, max rate-limits,  │
            │            sum lines over LIVE panes,  │
            │            append to @claude_glance    │
            └──────────────────────────────────────┘
                              │ set -g @claude_glance
                              ▼
            tmux status-right  (pure option interpolation)
```

### Component 1 — statusLine wrapper

New executable: `home/dot_local/bin/executable_claude-hud-usage-wrap`
(installed by chezmoi to `~/.local/bin/claude-hud-usage-wrap`).

Responsibilities, in order:

1. **Read stdin once** into a variable.
2. **Render**: pipe the captured JSON to the existing version-resolving claude-hud
   invocation (the exact `bun … src/index.ts` resolution currently inlined in
   `settings.json`), forwarding its stdout unchanged. This is the latency-critical
   path; nothing precedes it.
3. **Snapshot** (background, after render is dispatched): a single `jq -c` call
   extracts the consolidatable fields and writes them **atomically** (write to
   `<file>.tmp.$$`, then `mv` — `rename(2)` is atomic on the same filesystem) so
   the daemon never reads a half-written file.

Snapshot key: the transcript UUID (`transcript_path` basename, `.jsonl`
stripped) — stable per session and identical to the `sid` the daemon already
derives from `/proc`. Each snapshot also records `$TMUX_PANE` (inherited from the
Claude Code process env) and a write timestamp.

Snapshot schema (`<session>.json`):

```json
{
  "session": "05e66184-4aec-47f8-a41b-e66fd178275b",
  "pane": "%3",
  "ts": 1749100000,
  "cost_usd": 4.1234,
  "five_hour_pct": 48,
  "five_hour_resets_at": 1749112800,
  "seven_day_pct": 12,
  "seven_day_resets_at": 1749600000,
  "lines_added": 320,
  "lines_removed": 110
}
```

Field rules:
- Any field absent from stdin (older Claude Code, no cost yet) is emitted as
  `null`; the daemon treats `null` as "omit from aggregate," never as zero where
  that would mislead (e.g. rate-limit %).
- **Throttle**: skip the snapshot write if the existing file's mtime is younger
  than `~2s`. Bounds disk churn to ≤1 write / 2s / pane; a status bar does not
  need sub-2s cost resolution.
- **Degrade silently**: if `jq` is unavailable or stdin is not valid JSON, skip
  the snapshot entirely — the render path already completed, so the per-pane bar
  is unaffected.

`settings.json` `statusLine.command` is repointed from the inline claude-hud
invocation to this wrapper. Because the wrapper encapsulates the version
resolution, claude-hud auto-updates continue to work unchanged. The chezmoi
source `home/dot_claude/settings.json` is updated and applied; the live
`~/.claude/settings.json` is edited under the `claude-config` coord lock.

### Component 2 — daemon extension (`tmux-claude-glanced`)

The daemon already, in `rescan()`, walks live Claude procs and builds
`tr_of[pane]` / `win_of[pane]` / `proj_of[pane]` from each proc's
`CLAUDE_CODE_SESSION_ID` + `TMUX_PANE`. Two changes:

1. **`rescan()`**: also store `sid_of[pane]` (already in hand as `$sid`). This is
   the join key to the snapshot files.
2. **`tick()`**: after the existing per-window reduction, iterate the live panes
   and read each pane's snapshot (`$SNAP_DIR/${sid_of[pane]}.json`):
   - **cost** → sum across live panes. Gating on the live-pane set means a session
     that has exited is excluded automatically (its proc is gone, so it is not in
     `tr_of`), even though its snapshot file lingers.
   - **rate-limits** → these are account-global and identical across sessions;
     take the **max** of the non-null `five_hour_pct` / `seven_day_pct` seen (max
     is robust to a stale snapshot lagging a tick behind).
   - **lines** → sum `lines_added` / `lines_removed` across live panes.
   - **staleness/pruning**: snapshot files whose `session` is not in the current
     live set are pruned opportunistically (best-effort `rm`) so the directory
     does not grow unbounded across days.

The aggregate string appended to `@claude_glance` (push-if-changed preserved):

```
◉1 ●3 ⤒72%  ·  $4.12  ·  5h 48%  ·  7d 12%  ·  +320/-110
```

Rendering rules:
- The usage suffix is only built when `active > 0` (matches existing glance
  gating) **and** the `@claude_usage` toggle is on.
- Cost is dim/neutral (`@t_dim`); a segment is omitted entirely if its source
  data is absent across all live panes (e.g. no snapshot has cost yet).
- Rate-limit percentages reuse the existing green/yellow/red thresholds
  (`<60` / `60–85` / `≥85`) via a small `rl_color` helper (mirrors `ctx_color`).
  A compact reset countdown (`5h 48% (2h11m)`) is appended **only** when that
  window is in the yellow/red band, to keep the slim band slim when it doesn't
  matter.
- Colors are read from the `@t_*` palette at push time, so `theme set` recolors
  within one tick — consistent with the rest of the glance.

### Component 3 — config / wiring (`claude.conf`)

- New documented toggle near `@claude_ctx_limit`:
  `set -g @claude_usage 1` — master switch for the usage suffix (default on; set
  to `0` to render only the existing session/context glance).
- No change to the `status-right` format string: it already interpolates
  `@claude_glance`, into which the daemon now folds the usage suffix. This keeps
  the bar definition declarative and unaware of the new data.

## Data flow summary

| Datum | Source | Path to the bar |
|---|---|---|
| waiting/active/ctx% | transcript + /proc | daemon (existing) → `@claude_glance` |
| cost $ (summed) | statusLine stdin | wrapper → snapshot → daemon sum → glance |
| 5h / 7d rate-limit % | statusLine stdin | wrapper → snapshot → daemon max → glance |
| lines +/- (summed) | statusLine stdin | wrapper → snapshot → daemon sum → glance |

## Error handling & edge cases

- **Half-written snapshot**: prevented by temp-file + atomic `rename`.
- **`jq` missing**: wrapper skips snapshot; render unaffected; daemon shows the
  existing transcript-only glance.
- **Stale snapshot from a dead session**: excluded because cost/lines are summed
  only over live panes; file pruned opportunistically.
- **Rate-limit fields absent** (older Claude Code): `null` in snapshot; daemon
  omits the rate-limit segments rather than showing `0%`.
- **Multiple panes, same account**: rate-limits identical → `max` collapses them
  to one figure; cost/lines are genuinely per-session → summed.
- **Snapshot newer than daemon tick**: daemon reads on its ~1s tick; up to ~1s
  lag on cost is acceptable for a status bar.
- **chezmoi drift**: the `statusLine` repoint is made in the chezmoi source and
  applied, so a future `chezmoi apply` does not revert it.

## Testing (TDD)

Following the repo's `*.test.sh` convention (jq-fed fixtures, exit-code/output
assertions; see `claude/hooks/tests/guard-dangerous-commands.test.sh`):

1. **Wrapper extraction** — factor the jq snapshot extraction into a function (or
   a `--emit-snapshot` mode of the wrapper) and assert, against fixture stdin
   JSON, that the emitted snapshot has the right fields, that absent fields become
   `null`, and that invalid JSON yields no snapshot and a passthrough render.
2. **Wrapper passthrough** — assert claude-hud's stdout is forwarded byte-for-byte
   (stub the resolved command) and that the snapshot write does not pollute it.
3. **Aggregate reducer** — factor the cost-sum / rate-limit-max / lines-sum +
   formatting into a standalone function fed a set of fixture snapshot files;
   assert the resulting `@claude_glance` suffix for: single session, multiple
   sessions (cost sums, rate-limit collapses to max), missing-cost (segment
   omitted), and rate-limit color/countdown thresholds.

Performance invariant (asserted by inspection, not a unit test): no `#()` or
shell is added to any tmux format string; the wrapper adds one throttled `jq` +
background write per existing claude-hud spawn.

## Deliverables

1. `home/dot_local/bin/executable_claude-hud-usage-wrap` — new wrapper.
2. `home/dot_local/bin/executable_tmux-claude-glanced` — daemon patch
   (`sid_of`, snapshot read, aggregate suffix, pruning, `rl_color`).
3. `home/dot_tmux.conf.d/claude.conf` — `@claude_usage` toggle + doc.
4. `home/dot_claude/settings.json` — `statusLine` repoint to the wrapper
   (+ apply to live `~/.claude/settings.json` under the `claude-config` lock).
5. Tests under `claude/hooks/tests/` (or `test/`) for extractor + reducer.
6. This spec doc.

## Out of scope (YAGNI)

- Per-window cost glyphs (cost is a host-level concern; keep it in the aggregate).
- Historical / cumulative cross-session cost accounting or persistence.
- Backporting the suffix to the poll-fallback `tmux-claude-state` — the daemon is
  authoritative; parity there is a noted follow-up, not a blocker.
- Any change to the claude-hud plugin itself.
