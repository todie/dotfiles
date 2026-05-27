---
name: milestone-retarget
description: Bulk retarget Linear tickets across milestones — either move every issue from milestone A to milestone B, shift a milestone's target date by ±Nd/±Nw, or set an absolute date. Dry-run by default; with `--apply`, walks the changes sequentially with the same rate-limit-aware loop `linear-groom` uses (auto-injects `# bulk-file-spec: skip` when batch > 5), then runs a bidirectional validation pass (per `feedback_linear_deps_bidirectional.md`) to confirm the milestone actually landed via `get_issue` re-read. Use when the user says "shift milestone dates", "re-target milestone X to Y", "move all tickets from milestone A to milestone B", "rebalance milestone dates by N weeks". Args — required `--from <milestone-name>` and required `--project <name>`, one of (`--to <milestone-name>` | `--shift <±Nd|±Nw>` | `--set-date <YYYY-MM-DD>`), optional `--team <key>` (default TOD), `--apply`, `--batch <N>` (default 10), `--auto-bulk-marker` (default on).
---

# milestone-retarget — bulk milestone date/assignment with bidirectional safety pass

Re-target a Linear milestone in bulk: move every issue out of one milestone into another, shift a milestone's `target_date` by a relative delta, or set an absolute target date. Dry-run by default. The `--apply` loop is a copy of `linear-groom`'s rate-limit-aware sequential pattern, and every write is followed by a bidirectional `get_issue` re-read to confirm the milestone reference actually landed (Linear's save-issue response is a cached snapshot; relations and milestone IDs are not always reflected in the immediate response, per `feedback_linear_deps_bidirectional.md`).

## When to use

- User says "shift milestone X by 2 weeks", "move everything in milestone A to milestone B", "re-target the Phase 5 tickets to Phase 6", "rebalance milestone dates by N weeks"
- During a re-plan when the milestone calendar slips and you want one command rather than 30 manual save_issue calls
- After splitting/merging milestones to wholesale move a ticket population

**Don't** use this when:
- The retarget is judgment-heavy (move *some* tickets, not all) — that's `linear-groom`'s manual-review surfacing territory or direct `save_issue` calls in a loop with the user picking
- The user wants to file new tickets in the new milestone — that's `linear-file-spec` with `--milestone`
- The user wants to *delete* a milestone — the MCP can't delete; surface and let them act in the UI
- Scope is unscoped (no `--project`) — refuse, a workspace-wide milestone move is almost never the actual intent
- The same retarget is also a status change ("close all tickets in this milestone") — milestone-retarget only writes the `milestone` (or `target_date`) field; combining with status flips is out of scope to keep the validation pass simple

## Procedure

### 1. Parse args

- `--from <milestone-name>`: required, exact name match of the source milestone
- `--to <milestone-name>` OR `--shift <±Nd|±Nw>` OR `--set-date <YYYY-MM-DD>`: exactly one of the three must be given
  - `--to`: move every issue from `--from` into the named target milestone (issue-level write)
  - `--shift`: relative delta on the source milestone's `target_date` (milestone-level write; e.g. `+2w`, `-3d`)
  - `--set-date`: absolute new `target_date` on the source milestone (milestone-level write; e.g. `2026-07-01`)
- `--project <name>`: required, exact match
- `--team <key>`: default `TOD`
- `--apply`: execute the changes; default is dry-run
- `--batch <N>`: max writes per second (default `10`)
- `--auto-bulk-marker` / `--no-auto-bulk-marker`: when the apply loop writes more than 5 `save_issue` calls, auto-inject `# bulk-file-spec: skip` into the description field. Default: on. Disable only when you know the batch will stay under 5.

If `--project` is missing, refuse: `milestone-retarget requires --project — refusing to scan all of Linear`.

If zero or more than one of `--to` / `--shift` / `--set-date` is given, refuse: `milestone-retarget requires exactly one of --to, --shift, or --set-date`.

### 2. OAuth + scope preflight

Run one cheap call: `mcp__claude_ai_Linear__list_teams`.

- If it succeeds → OAuth is alive. Verify the resolved team key exists.
- If it fails with an auth-shaped error → abort with: `Linear OAuth expired. Re-auth with: /mcp` and stop. Do NOT continue.

Resolve `--project` to an ID via `list_projects`. Abort if no exact match.

Resolve `--from` to a milestone ID via `list_milestones` (filter by project). Abort if no exact match.

If `--to` is given, resolve it the same way. If the resolved `--to` ID equals the `--from` ID, refuse: `--to and --from resolve to the same milestone — nothing to move`.

If `--shift` is given, parse it as `^([+-])(\d+)([dw])$`. Refuse on any other shape. Read the source milestone's current `target_date`; if null, refuse: `--shift requires a current target_date on the --from milestone (currently null) — use --set-date instead`.

If `--set-date` is given, parse as ISO date `YYYY-MM-DD`. Refuse on any other shape.

Print a one-line preflight summary:

```
Preflight: team=TOD (ok) · project=Reverie (ok) · from="Phase 5" (ok) · op=to:"Phase 6" · mode=dry-run
```

### 3. Compute the plan

**For `--to` (issue-level move):**

List all issues in scope with `milestone=from_id` via `mcp__claude_ai_Linear__list_issues`. Cap at 200 tickets. If more, abort: `--from milestone has >200 issues — narrow scope (split the move in two passes by sub-project or labels)`.

The plan is: for each issue, one `save_issue(id=issue.id, milestone=to_id)` call.

**For `--shift` (milestone-level date arithmetic):**

Compute new date = `current.target_date + delta`. (Weeks: × 7 days.) The plan is: one `save_milestone(id=from_id, targetDate=new_date)` call. List the issues in scope only for the report — they will all inherit the new date implicitly, no per-issue writes.

**For `--set-date` (milestone-level absolute):**

Same shape as `--shift` but the new date is the literal `--set-date` value. One `save_milestone(id=from_id, targetDate=new_date)` call.

### 4. Dry-run output (default)

Print a "Before" table of in-scope issues (or the milestone, for date-only ops):

For `--to`:

| # | ID | Title | State | Current milestone |
|---|----|-------|-------|-------------------|
| 1 | TOD-491 | Wire mesh telemetry | In Progress | Phase 5 |
| 2 | TOD-492 | Wire mesh metrics | Todo | Phase 5 |

For `--shift` / `--set-date`:

| Milestone | Current target_date | New target_date |
|-----------|---------------------|-----------------|
| Phase 5 | 2026-06-15 | 2026-06-29 |

Then one of these plan summaries:

```
Plan: move 2 issues from "Phase 5" → "Phase 6". Re-run with --apply to write.
Plan: shift "Phase 5" target_date from 2026-06-15 to 2026-06-29 (+2w). Re-run with --apply to write.
Plan: set "Phase 5" target_date to 2026-07-01 (was 2026-06-15). Re-run with --apply to write.
```

Exit. Do not call any save.

### 5. Apply mode (`--apply`)

**5a. Inject the bulk marker if needed.**

For `--to` retargets, if planned-writes > 5 and `--auto-bulk-marker` is on (default), log once: `auto-bulk-marker: injecting # bulk-file-spec: skip (N writes > 5-call threshold)`. The marker is appended as a trailing line to the description field of each `save_issue` call. For milestone-level ops (`--shift`, `--set-date`) the bulk marker does not apply — that's a single `save_milestone` write, no rate-limit risk.

**5b. Execute the writes — forward pass.**

For each planned write:

- `save_issue(id=issue.id, milestone=to_id)` for `--to`, or `save_milestone(id=from_id, targetDate=new_date)` for the others
- Sequential, never parallel. Sleep `1000 / batch` ms between calls (default 100ms → 10/sec).
- On rate-limit error (HTTP 429 or MCP-level rate-limit shape): exponential backoff starting at 2s, doubling each retry, max 5 retries. After 5 → abort the apply loop and report what landed.
- On any other error: abort the apply loop immediately, report what landed, surface the error.

Collect the list of touched issue IDs (for `--to`) or the touched milestone ID (for `--shift` / `--set-date`).

**5c. Bidirectional validation pass.**

This is the safety pass from `feedback_linear_deps_bidirectional.md`. The Linear MCP's `save_issue` response is a cached snapshot — milestone changes are not always reflected in the immediate response, and `updatedAt` does not bump for some field updates. The only way to confirm the write landed is a fresh `get_issue` (or `get_milestone`) call.

For `--to` retargets:

- For each touched issue ID, call `mcp__claude_ai_Linear__get_issue(id, includeRelations: false)` and assert `result.milestone.id == to_id`.
- Build a "validation" table: `id | title | expected_milestone | actual_milestone | ✓/✗`.
- Any row where `actual ≠ expected` is a **failed write** — print it loudly. Suggest re-running the apply (which is idempotent — re-applying a successful write is a no-op).
- Sequential. Sleep `1000 / batch` ms between calls — same rate-limit budget as the writes. This pass roughly doubles the wall-clock time of the apply; the user should expect that.
- Cap the validation pass at 50 issues. If the write batch was larger, validate a random sample of 50 and surface the sampling caveat in the report. This trades full coverage for predictable wall-time at large scope.

For `--shift` / `--set-date` retargets:

- Call `mcp__claude_ai_Linear__get_milestone(id=from_id)` and assert `result.targetDate == new_date` (ISO date string compare).
- Single read, no sampling needed.

**5d. Final report.**

Print the apply tally + the validation tally:

```
Applied: 12 writes, 0 failures, 0 rate-limit retries
Validated: 12/12 milestone references landed (100%)
```

Or, on partial failure:

```
Applied: 12 writes, 0 failures, 0 rate-limit retries
Validated: 10/12 milestone references landed — 2 failures listed below.

| ID | Title | Expected milestone | Actual milestone |
|----|-------|--------------------|------------------|
| TOD-495 | ... | Phase 6 | Phase 5 |
| TOD-499 | ... | Phase 6 | (none) |

Re-run the same command to retry the 2 failed writes (idempotent).
```

### 6. Exit

Return cleanly. Do NOT auto-loop into another retarget. If the user is doing a multi-milestone re-plan, they call the skill once per milestone pair.

## Safety invariants

- **Always** run the OAuth preflight first. Discovering the token is dead mid-batch is the worst outcome.
- **Always** require `--project`. Cross-project milestone retargets are almost never the actual intent.
- **Always** run the bidirectional validation pass after `--apply`. The forward pass is not enough — the Linear save-response cache means a write can silently fail.
- **Never** auto-fix anything beyond the requested milestone field. This skill writes `milestone` (on issues) or `targetDate` (on milestones), nothing else.
- **Never** call `save_issue` in parallel. Sequential + rate-limit backoff is the only safe write pattern.
- **Never** continue after an auth error. Surface the `/mcp` reauth and stop.
- **Never** combine milestone retarget with status flips, label edits, or assignment changes — keeps the validation pass simple and the blast radius small.
- **Always** cap the scope. >200 issues per milestone is a sign the user should split the move.
- **Always** print the resolved scope before doing anything — wrong-milestone retargets are a one-typo disaster.

## Example invocations

**Move all Phase 5 tickets to Phase 6:**

```
milestone-retarget --project Reverie --from "Phase 5: Auto-Capture & Write-Gate" --to "Phase 6: Auto-Capture Phase 2"
```

Dry-run output:

```
Preflight: team=TOD (ok) · project=Reverie (ok) · from="Phase 5: Auto-Capture & Write-Gate" (ok) · op=to:"Phase 6: Auto-Capture Phase 2" · mode=dry-run

Before:
| # | ID      | Title                   | State       | Current milestone                     |
|---|---------|-------------------------|-------------|---------------------------------------|
| 1 | TOD-491 | Wire mesh telemetry     | In Progress | Phase 5: Auto-Capture & Write-Gate    |
| 2 | TOD-492 | Wire mesh metrics       | Todo        | Phase 5: Auto-Capture & Write-Gate    |
| 3 | TOD-493 | Wire mesh dashboards    | Backlog     | Phase 5: Auto-Capture & Write-Gate    |

Plan: move 3 issues from "Phase 5: Auto-Capture & Write-Gate" → "Phase 6: Auto-Capture Phase 2". Re-run with --apply to write.
```

After `--apply`:

```
... (preflight + plan as above) ...

auto-bulk-marker: skipping (3 writes < 5-call threshold)

Applied: 3 writes, 0 failures, 0 rate-limit retries
Validated: 3/3 milestone references landed (100%)
```

**Shift Phase 5 target_date by +2 weeks:**

```
milestone-retarget --project Reverie --from "Phase 5: Auto-Capture & Write-Gate" --shift +2w --apply
```

Output:

```
Preflight: team=TOD (ok) · project=Reverie (ok) · from="Phase 5: Auto-Capture & Write-Gate" (ok) · op=shift:+2w · mode=apply

Before:
| Milestone                            | Current target_date | New target_date |
|--------------------------------------|---------------------|-----------------|
| Phase 5: Auto-Capture & Write-Gate   | 2026-06-15          | 2026-06-29      |

Plan: shift "Phase 5" target_date from 2026-06-15 to 2026-06-29 (+2w).

Applied: 1 milestone write, 0 failures.
Validated: target_date now 2026-06-29 (✓).
```

**Set absolute target_date:**

```
milestone-retarget --project Reverie --from "Phase 5: Auto-Capture & Write-Gate" --set-date 2026-07-01 --apply
```

## Future extensions

- **`--state-filter <csv>`** to restrict the move to issues in specific states (e.g. only Backlog + Todo, leave In Progress alone)
- **`--exclude <TOD-ids>`** csv of ticket IDs to skip during a `--to` move (manual carve-out)
- **`--dry-validate`** to run the validation pass on a sample of already-moved tickets without doing any writes — useful when you suspect a previous retarget silently failed
- **Cycle-detection on `--shift`** — if the new date crosses another milestone's date, warn before applying (the user may want to retarget that milestone too)
- **Slack post** of the apply summary, matching `linear-groom`'s `--slack` flag shape
- **Cron loop** for recurring milestone date shifts (e.g. "every Monday shift the active milestone by +5d if the team is behind"), pair with `/schedule`
