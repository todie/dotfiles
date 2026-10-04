---
name: linear-groom
description: Audit a Linear scope (team / project / milestone / assignee, or the whole workspace as a census) for tracker drift and emit a grooming plan — triage-queue age, stale In Progress, WIP overload, stale Todo, dormant projects, parents whose children are all done, merged-PR tickets still open, missing project/labels/estimate/assignee, orphan-of-milestone, duplicate titles, asymmetric relations. Dry-run by default; `--apply` executes only the evidence-backed mechanical fixes, one write at a time through `linearctl`, each re-read. Never the Linear MCP for writes. Use when the operator says "groom Linear", "audit the backlog", "what's stale", "clean up tickets", "take lead of grooming", or on the weekly hygiene loop. Args — scope flags (`--team <key...>|all`, `--project <name>`, `--milestone <name>`, `--assignee <who>`), `--check <csv>`, thresholds (`--stale-started 14d`, `--stale-todo 30d`, `--triage-sla 7d`, `--project-idle 30d`, `--wip-limit 10`), `--apply`, `--export <path>`, `--ai-suggest`, `--slack <channel>`.
---

# linear-groom — tracker census + evidence-backed fix loop

Walk a Linear scope, surface every drift signal as a structured row, write the
report to a file, and either stop (default) or apply the fixes that need no
judgment. Grooming, not arbitrary bulk editing: anything that needs a human
call is surfaced with a drafted command, never executed.

**v2 (2026-10-04).** Rewritten onto `linearctl` after the first workspace-wide
census (331 issues in Triage, 87 In Progress on one assignee, 31 In Progress
stale beyond 14 days, 40 projects In Progress with most untouched since July).
Three things changed and why:

1. **Writes go through `linearctl`, never the Linear MCP.** The claude.ai Linear
   connector is the held surface under `hold-batch-ops-until-root-cause.md`
   (OPS-448): one write per message, and a body that names other ticket IDs
   fans out server-side. `linearctl` is the sanctioned path.
2. **The `# bulk-file-spec: skip` marker is gone.** v1 injected it into every
   description on batches over five writes. That marker is the OPS-448 wiper:
   descriptions were replaced with it across three incident windows and four
   tickets have no recoverable source. A rate-limit workaround that rewrites
   descriptions is not a workaround. Rate limits are handled by pacing and
   `linearctl ratelimit`, nothing else. (`milestone-retarget` still carries the
   v1 copy of this loop; fix it there too, tracked separately.)
3. **No 200-ticket abort and no default team.** The estate's active teams are
   CER, OPS, EST, SEC, ONB (not TOD); scope is always explicit. Large scopes
   produce a file, not a terminal dump, and every table is capped per
   category with an "…N more" line and the full list in the export.

## When to use

- "groom Linear", "audit the backlog", "what's stale in <project>", "clean up
  tickets", "who is overloaded", "triage queue status"
- Before a planning session, so human time goes to judgment, not enumeration
- The weekly hygiene loop: `/loop 7d /linear-groom --team CER,OPS,EST,SEC`
- After a lane hands over work, to find the tickets it left In Progress

**Don't** use this for: arbitrary bulk edits (call `linearctl update --stdin`
with a plan you wrote), filing (`linear-file-spec`, `file-bug`, `linearctl
park`), milestone moves (`milestone-retarget`), or merging duplicates (the
report names the pair; a human merges in the UI).

## Preconditions

```bash
linearctl --version      # 0.7.0 or later; `label list` and `project list --team` need it
linearctl whoami         # proves LINEAR_API_KEY works; abort on failure, do not retry
linearctl ratelimit      # shared org budget (2500/hr); abort below 300 remaining
```

A stale `linearctl` ahead on PATH has happened (a 0.2.0 binary sat first on the
operator's deck PATH until 2026-10-04). Check the version, not the presence.

The Linear MCP (`mcp__claude_ai_Linear__*`) may be used for READS that
`linearctl` lacks (notifications, project lead/target dates, relations), with a
`fields` list every time. Never for a write, never for a comment.

## Procedure

### 1 · Parse args and resolve scope

- `--team <key...>|all` · `--project <name>` · `--milestone <name>` ·
  `--assignee <who>` (`me`, email, display name). At least one is required;
  `--team all` is a census and is allowed, the output goes to a file.
- `--check <csv>` from: `triage,stale-started,stale-todo,wip,project-idle,
  parent-done,pr-xref,project,labels,estimate,assignee,orphan,duplicate,
  relation-mirror` (default: all except `pr-xref`, which needs `--repo`).
- Thresholds: `--stale-started 14d` · `--stale-todo 30d` · `--triage-sla 7d`
  · `--project-idle 30d` · `--wip-limit 10`.
- `--repo <owner/repo...>`: enables `pr-xref` via `linearctl xref`.
- `--apply` · `--export <path>` (default
  `~/handoffs/linear-groom/<date>-<scope-slug>.md`) · `--ai-suggest` ·
  `--slack <channel>`.

Refuse with no scope flag: `linear-groom requires --team, --project,
--milestone or --assignee`. Resolve `--project`/`--milestone` to IDs
(`linearctl project list --team <key> --json`, `linearctl milestone --project
<id> --json`); abort on a non-exact match. Print the resolved scope first:

```
Preflight: linearctl 0.7.0 · viewer=ctodie · ratelimit=2210 · team=CER,OPS · project=— · checks=all · mode=dry-run · export=~/handoffs/linear-groom/2026-10-04-cer-ops.md
```

### 2 · Collect, once

Pull every surface a single time into the scratchpad; the checks read files,
not the API. Only open states (Triage, Backlog, Todo, In Progress, In Review)
are drift candidates.

```bash
linearctl stale  --team <keys> --older-than 1d --json > stale.json    # every open issue with daysStale
linearctl triage --team <keys> --json               > triage.json   # Triage-state + unassigned/unestimated/no-priority
linearctl project list --team <key> --json          > projects-<key>.json   # per team; the flag is required
linearctl milestone gap --project <id> --json       > gap-<id>.json  # only for --project scopes
linearctl xref --repo <r> --team <keys> --json      > xref-<r>.json  # only with --repo
```

Issue bodies and relations are fetched on demand (`linearctl show <id> --json`,
MCP `get_issue` with `includeRelations`), capped as each check states.

### 3 · Checks

| check | signal | threshold |
|---|---|---|
| `triage` | issues in a Triage state, per team: count, oldest age, share with no priority | age > `--triage-sla` is the row |
| `stale-started` | In Progress / In Review with `daysStale` > threshold | `--stale-started` |
| `stale-todo` | Todo with `daysStale` > threshold (Backlog is meant to be stale and is never a signal) | `--stale-todo` |
| `wip` | one assignee holding more In Progress + In Review than the limit | `--wip-limit` |
| `project-idle` | project state In Progress and (no open issue updated within `--project-idle`, or zero open issues); also no lead, no target date | `--project-idle` |
| `parent-done` | open parent whose sub-issues are all completed or canceled | none |
| `pr-xref` | ticket referenced by a merged PR but still open (`linearctl xref`) | none |
| `project` | no project, team scope only | none |
| `labels` · `estimate` · `assignee` | empty labels; null estimate on non-Backlog; null assignee on In Progress / In Review | none |
| `orphan` | no milestone, in a project that has milestones | none |
| `duplicate` | same normalized title, or Levenshtein ≥ 0.85 within one project; emit a pair row tagged `exact` or `fuzzy:<score>` | none |
| `relation-mirror` | `blocks` without the mirrored `blockedBy` on the other side; read-only; first 20 tickets with relations, then a capped warning | none |

A ticket may carry several signals; one row per ticket, signals joined.

### 4 · Fix plan — mechanical only

| signal | auto-fixable | action under `--apply` |
|---|---|---|
| `pr-xref` | yes, evidence is the merged PR | `linearctl xref --repo <r> --fix --apply`, one ticket at a time, then `linearctl show <id> --json` to confirm the state |
| `parent-done` | yes, evidence is the children | `linearctl comment <id> "children all completed: <list>"` then `linearctl close <id>`; re-read |
| `project` | only if the team has exactly one active project | `linearctl update <id> --project <id>`; re-read |
| `stale-started` | opt-in only: `--demote-after <days>` | comment stating the age and the reason, then `--state Todo`; re-read. Default off; the operator ratifies the threshold once |
| everything else | no | report with a drafted `linearctl` command the human can paste |

Every write is sequential, re-read by a different call than the one that wrote
it, and spaced ≥ 250 ms. On HTTP 429: back off 2 s doubling, five tries, then
stop and report what landed. On any other error: stop, report, surface.

**Never:** write through the MCP; put ticket IDs in an MCP comment body; close
without the evidence named above; delete anything; touch tickets another lane
owns without telling that lane first (name the lane in the report; send one
bundle on the mesh, not a drip); write descriptions; rewrite labels in bulk.

### 5 · Report

Write the export file, then print to the terminal: the preflight line, a count
per signal, the top ten rows of "Auto-fixable" and of "Manual review", and the
path. If the full report exceeds about 40 lines, open the file in `$EDITOR`
(`zedw` fallback) per `presentation-and-decisions.md`; the terminal keeps the
orientation only.

Report sections, in order:

1. **Census** — one line per team: open · Triage (oldest) · In Progress · WIP
   per assignee over the limit.
2. **Auto-fixable** — `| ID | Title | Signal | Evidence | Command |`.
3. **Manual review** — `| ID | Title | Signals | Owner lane | Last updated |`,
   grouped by owner lane (project → lane map from `herdr agent list` cwd when
   derivable; else "unowned"), capped at 25 rows per group with "…N more".
4. **Projects** — `| Project | Team | Lead | Target | Open | Last activity | Signals |`.
5. **Decisions for the operator** — the forks this run cannot decide (close vs
   demote vs reassign for each stale cluster; whether to triage a queue; whether
   a dormant project is Done, Paused or still live). These go through
   `AskUserQuestion`, batched, never as prose bullets.

Summary line: `N scanned · K auto-fixable · M manual · P projects flagged ·
export <path>. Re-run with --apply to write the K fixes.`

### 6 · `--ai-suggest` (dry-run only, never applied)

One Sonnet subagent per 25 tickets, fed `linearctl show <id> --json` bodies,
proposing labels / estimate / project / milestone with `high|medium|low`
confidence. Budget 100 tickets; refuse above it. Written to a fourth table in
the export; `--apply` ignores it even when both flags are passed.

### 7 · `--slack <channel>`

Post the census lines and counts plus the top ten manual-review rows in a code
block via `mcp__claude_ai_Slack__slack_send_message`. Over 30 rows: counts plus
the export path only. Slack failure never fails the run.

### 8 · Exit

Return. Do not loop into another scope; the operator wraps the skill in `/loop`.

## Safety invariants

- Scope is explicit; `--team all` is allowed and writes a file.
- Preflight through `linearctl whoami` + `ratelimit`; auth failure is a stop.
- Writes: `linearctl` only, sequential, re-read, paced. The Linear MCP is
  read-only here, with `fields`, and never carries ticket IDs in a body.
- No description writes of any kind. No `# bulk-file-spec: skip`.
- Closes need evidence (merged PR, all children done, or a live check named in
  the comment). Demotion is opt-in and ratified once by the operator.
- Decisions go through `AskUserQuestion`; long reports go to a file + editor.
- Tickets a lane owns: tell the lane before writing; one bundle.

## Example

```
/linear-groom --team CER,OPS,EST,SEC --stale-started 14d --wip-limit 10
```

```
Preflight: linearctl 0.7.0 · viewer=ctodie · ratelimit=2210 · team=CER,OPS,EST,SEC · checks=all · mode=dry-run · export=~/handoffs/linear-groom/2026-10-04-cer-ops-est-sec.md

Census
| team | open | triage (oldest) | in progress | wip > 10 |
| OPS  | 1102 | 440 (125d)      | 31          | ctodie 24 |
| CER  |  811 | 0               | 46          | ctodie 38 |
...
Auto-fixable (3)   Manual review (71)   Projects flagged (29)
Report opened in $EDITOR. Re-run with --apply to write the 3 fixes.
```

## Future extensions

- `linearctl groom` as a native subcommand, so the census is one call
- Owner-lane map as a file (`~/.agents/lane-map.toml`) instead of cwd inference
- Semantic duplicate detection (embeddings) above the Levenshtein pass
- A `--since` window for incremental runs on large teams
