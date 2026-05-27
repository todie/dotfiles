---
name: milestone-retarget
description: Bulk-move Linear tickets between milestones or shift milestone target dates, with a dry-run safety pass and backward-validation. Use when the user says "shift milestone dates", "re-target milestone X to Y", "move all tickets from milestone A to milestone B", "rebalance milestone dates by N weeks". Args — `--from <milestone-name>` required, one of `--to <milestone-name>` / `--shift <±Nd|±Nw>` / `--set-date <YYYY-MM-DD>`, `--team <key>` default TOD, `--project <name>` required, `--apply` to write (default dry-run).
---

# milestone-retarget — bulk milestone date/assignment with safety pass

Move tickets from one milestone to another, or shift / set a milestone's target date. Dry-run by default — always prints a before/after table before writing anything. Apply mode loops `save_issue` (or `save_milestone` for date-only) in rate-limited batches, then backward-validates each write.

## When to use

- User says "shift milestone dates", "re-target milestone X to Y", "move all tickets from milestone A to B", "rebalance milestone dates by N weeks", "push milestone back 2 weeks"
- After a planning session where scope slips and tickets need to migrate
- Date arithmetic when a release window shifts by a fixed interval

**Don't** use this when:
- The user wants to edit individual ticket fields beyond milestone assignment — use `save_issue` directly or `linear-groom --apply`
- The user wants to create new milestones — `list_milestones` and `save_milestone` directly
- Scope is unscoped (no `--project`) — refuse; whole-workspace milestone operations are dangerous

## Args

```
--from <milestone-name>    required   source milestone (exact name match)
--to <milestone-name>      move mode  target milestone for all tickets in --from
--shift <±Nd|±Nw>          date mode  shift --from milestone's target date by ±N days/weeks
--set-date <YYYY-MM-DD>    date mode  set --from milestone's target date absolutely
--team <key>               optional   Linear team key (default: TOD)
--project <name>           required   Linear project name
--apply                    optional   write changes (default: dry-run, print only)
```

One of `--to`, `--shift`, or `--set-date` is required. `--to` and `--shift/--set-date` are mutually exclusive.

## Procedure

### 1. Parse and validate args

- Require `--from` and `--project`; require exactly one of `--to`, `--shift`, `--set-date`.
- In date modes (`--shift`/`--set-date`), `--to` is invalid — error immediately.
- Parse `--shift` format: `+2w` → +14 days, `-1d` → -1 day. Reject malformed patterns.

### 2. Resolve milestone IDs

- `list_teams` → confirm team key.
- `list_projects` → get project ID.
- `list_milestones` for the project → match `--from` and `--to` (if move mode) by exact name. Error if not found.

### 3. List affected issues

In move mode: `list_issues` with `milestone=from-id`. Paginate until exhausted.
In date modes: affected entity is the milestone itself, not individual issues.

### 4. Print the before-state table

Move mode:
```
milestone-retarget: moving N tickets from "<from>" → "<to>"
──────────────────────────────────────────────────────
  TOD-42  Implement GPU scheduler                    [In Progress]
  TOD-55  Metrics export pipeline                    [Todo]
  ... (N total)
──────────────────────────────────────────────────────
Dry-run. Pass --apply to execute.
```

Date mode:
```
milestone-retarget: shifting "<from>" target date
  Current:  2026-06-15
  New:      2026-06-29  (+2w)
Dry-run. Pass --apply to execute.
```

If `--apply` is not given, stop here.

### 5. Apply changes (rate-limited)

Move mode — loop `save_issue` per ticket:
- Batch size default 10. If batch > 5, auto-inject `# bulk-file-spec: skip` into each `save_issue` description field (per `feedback_linear_mcp_quirks.md` rate-limit protocol).
- Sequential — no concurrent MCP calls.
- Log each write: `TOD-42 → milestone: <to-id> ... ok`.

Date mode — call `save_milestone` (or `save_issue` per-ticket if the MCP lacks `save_milestone`) with the computed `targetDate`.

### 6. Backward-validation pass

Per `feedback_linear_deps_bidirectional.md`: after every write, `get_issue(id, includeRelations: true)` and assert `milestone.id == expected`. If a write silently failed (milestone not updated), surface it as a warning row. Never silently continue past a validation miss.

### 7. Report

```
milestone-retarget: applied
  42/42 tickets moved to "<to>"   ✓
  0 validation misses
```

Or with misses:
```
  40/42 tickets moved   ✓
  2 validation misses — re-run or fix manually:
    TOD-77  (milestone still: <old-id>)
    TOD-88  (milestone still: <old-id>)
```

## Relationship to other skills

| Skill | Verb |
|---|---|
| `milestone-retarget` | bulk ticket reassignment or milestone date shift |
| `linear-groom` | drift detection + mechanical fixes (project-attach, stale labels) |
| `linear-file-spec` | file tickets from spec sections |

`milestone-retarget` is not an extension of `linear-groom`: groom detects drift across many dimensions; retarget is a single targeted bulk mutation. They share the rate-limit-aware apply pattern and the backward-validation idiom.
