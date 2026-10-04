---
name: milestone-retarget
description: Bulk retarget Linear tickets across milestones — move every issue from milestone A to milestone B, shift a milestone's target date by ±Nd/±Nw, or set an absolute date. Dry-run by default; `--apply` writes through `linearctl`, sequentially, each change re-read by a different call. Never the Linear MCP for writes; never any marker injection. Use when the user says "shift milestone dates", "re-target milestone X to Y", "move all tickets from milestone A to milestone B", "rebalance milestone dates by N weeks". Args — required `--team <key>`, `--project <name>`, `--from <milestone-name>`; exactly one of `--to <milestone-name>` / `--shift <±Nd|±Nw>` / `--set-date <YYYY-MM-DD>`; optional `--apply`, `--batch <N>`.
---

# milestone-retarget — bulk milestone date/assignment moves

**v2 (2026-10-04).** Rewritten onto `linearctl`. Three v1 behaviors are gone and
must never return:

1. **The `# bulk-file-spec: skip` marker is deleted.** v1 injected it into
   descriptions on batches > 5 writes; that marker is the OPS-448 wipe
   signature — descriptions were replaced with it across three incident
   windows. This skill never touches descriptions at all now.
2. **No Linear-MCP writes.** All writes go through `linearctl`, one at a time
   (`hold-batch-ops-until-root-cause.md`). MCP reads are allowed, with a
   `fields` list, where linearctl lacks a read (see step 3).
3. **No default team.** `--team` is required.

## When to use

- "shift milestone X by 2 weeks", "move everything in milestone A to B",
  "re-target the Phase 5 tickets to Phase 6", "rebalance milestone dates"
- A re-plan when the milestone calendar slips and one command beats 30 manual
  edits

**Don't** use when:
- The retarget is judgment-heavy (move *some* tickets) — that's `linear-groom`'s
  manual-review surface, or hand-picked `linearctl update <id> --milestone` calls
- You want to *delete* a milestone — `linearctl milestone delete <uuid>` exists
  (dry-run unless `--yes`) but is deliberately not this skill's job; do it
  deliberately, by hand
- The retarget is also a status change ("close everything in this milestone") —
  this skill writes only milestone fields; combining keeps verification simple

## Preconditions

```bash
linearctl --version   # >= 0.7.0
linearctl whoami      # abort on auth failure, no retry
linearctl ratelimit   # abort below 300 remaining
```

## Procedure

### 1. Parse args

- `--team <key>`: required. Active teams: CER, OPS, EST, SEC, ONB, TOD, RD,
  BIZ, BRAND, VES.
- `--project <name>`: required, exact match. Refuse without it: cross-project
  retargets are almost never the intent.
- `--from <milestone-name>`: required, exact match.
- Exactly one of:
  - `--to <milestone-name>` — move every issue in `--from` into `--to`
    (issue-level writes)
  - `--shift <±Nd|±Nw>` — relative delta on `--from`'s target date
    (milestone-level write)
  - `--set-date <YYYY-MM-DD>` — absolute target date on `--from`
- `--batch <N>`: max writes per second (default 4 — ≥ 250 ms spacing)
- `--apply`: write. Default is dry-run.

Zero or 2+ of `--to`/`--shift`/`--set-date` → refuse and say so.

### 2. Resolve (reads)

```bash
linearctl project list --team <key> --json     # exact name → project id; abort on miss/tie
linearctl milestone --project <id> --json      # exact name → {from_id, from_targetDate}; same for --to
```

- `--to` resolving to the same id as `--from` → refuse: nothing to move.
- `--shift` with a null current `targetDate` → refuse: use `--set-date`.
- `--shift` shape must match `^([+-])(\d+)([dw])$`; `--set-date` must be ISO.

Print the resolved scope before anything else:

```
Preflight: linearctl 0.7.0 · team=CER · project=Reverie · from="Phase 5" (2026-06-15) · op=to:"Phase 6" · mode=dry-run
```

### 3. Enumerate in-scope issues (read)

linearctl 0.7.0 cannot filter issues by milestone (no `--milestone` on
`pull`/`search`, no milestone field on `show --json` — requested from the
linearctl lane 2026-10-04). Until that lands, enumerate with an MCP **read**:

- `mcp__claude_ai_Linear__list_issues` filtered to project + milestone, with a
  `fields` list (`id, identifier, title, state, milestone`) — reads only, never
  a write, never a comment.

Cap at 200 issues; above that, refuse and split the move (by label or
sub-project). Once `linearctl pull --project <id> --milestone <name> --json`
exists, switch to it and drop this paragraph.

For `--shift` / `--set-date`, enumeration is for the report only — issues
inherit the milestone date implicitly.

### 4. Dry-run output (default)

`--to`: table of in-scope issues (id, title, state).
`--shift`/`--set-date`: `| milestone | current target | new target |`.

Then: `Plan: move N issues from "A" → "B". Re-run with --apply to write.` (or
the date equivalent). Exit.

### 5. Apply

**`--to` move** — per issue, sequential, ≥ 250 ms apart:

```bash
linearctl update <id> --milestone <to-uuid> --json
```

Pass the milestone **UUID**, not the name — id lookup is unambiguous.

**`--shift` / `--set-date`** — one write; `milestone update` is itself dry-run
unless `--apply`:

```bash
linearctl milestone update <from-uuid> --target-date <YYYY-MM-DD> --apply --json
```

On HTTP 429: back off 2 s doubling, five tries, then stop and report what
landed. On any other error: stop, report, surface. Never retry-storm; never
patch around a rate limit by touching descriptions.

### 6. Re-read validation pass

Every write is verified by a **different** call than the one that wrote it.

- `--to`: re-read each touched issue and assert its milestone == `--to` id.
  Today that is an MCP read (`get_issue`, `fields: [identifier, milestone]`) —
  linearctl `show --json` lacks the field (same lane request as step 3). Cap
  the pass at 50 issues; above that, validate a random sample of 50 and say so.
- `--shift` / `--set-date`: `linearctl milestone --project <id> --json`, assert
  `targetDate` == new date.

Build a validation table `| id | expected | actual | ✓/✗ |`. Any ✗ is a failed
write — print loudly; re-running the same command is idempotent.

### 7. Report

```
Applied: N writes, 0 failures, R rate-limit retries
Validated: N/N milestone references landed (100%)
```

Partial failure: list the misses, state that a re-run retries them.

## Safety invariants

- Scope is explicit: `--team` + `--project` + `--from`, always resolved and
  printed first. No defaults, no inference.
- Writes: `linearctl` only, sequential, ≥ 250 ms pacing, re-read by a different
  call. The Linear MCP is read-only here, always with `fields`.
- This skill writes only `milestone` (issues) or `targetDate` (milestones) —
  never descriptions, labels, states, assignees.
- **No marker injection, ever.** `# bulk-file-spec: skip` is the OPS-448 wipe
  signature; any skill text reintroducing it is a defect.
- Dry-run by default; `--apply` writes; auth failure stops, never retries.

## Examples

```
milestone-retarget --team CER --project Reverie --from "Phase 5" --to "Phase 6"
milestone-retarget --team CER --project Reverie --from "Phase 5" --shift +2w --apply
milestone-retarget --team CER --project Reverie --from "Phase 5" --set-date 2026-07-01 --apply
```

## Example script

`scripts/milestone-shift-example.sh` — runnable `--shift` dry-run against a
real project+milestone (args), with the apply path behind `APPLY=1`, including
the post-write `milestone --json` assertion.

## Future extensions

- `--state-filter <csv>` to restrict a `--to` move to specific states
- `--exclude <ids>` carve-out list
- Cross-milestone date-collision warning on `--shift`/`--set-date`
- Drop the MCP reads once `pull --milestone` / `show --json milestone` land
