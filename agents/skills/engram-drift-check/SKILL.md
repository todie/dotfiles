---
name: engram-drift-check
description: Diff session-start engram observations against ground truth for verifiable claims (Linear team keys, project names, file paths, ticket IDs). Surfaces stale facts as a table. Read-only by default; `--apply` writes a superseding observation and soft-links the stale one. Also runs automatically at session start via the session-bootstrap-engram-drift hook. Use when the user says "is my engram memory current", "check memory for stale facts", "engram drift". Args — `--project <name>` default detected from cwd, `--checks <csv>` default `linear-team-key,project-names,recent-tickets`, `--apply` to write supersessions.
---

# engram-drift-check — diff engram observations against ground truth

Fetch all engram observations for a project, extract verifiable factual claims (Linear team keys, project names, ticket IDs, file paths), and verify each against live ground truth. Surface contradictions as a table; optionally write superseding observations via engram's supersession protocol.

## When to use

- User says "is my engram memory current", "check memory for stale facts", "engram drift"
- Automatically at session start (invoked by `session-bootstrap-engram-drift.sh` hook in dry-run mode)
- After a project rename, team-key change, or major structural refactor — stale facts accumulate fast

**Don't** use this when:
- The user wants to *write* a new memory observation — use `engram:memory` directly
- The project has no engram observations yet — skill will report "no verifiable claims found" and exit cleanly
- Running in CI or unattended contexts without `--apply` — dry-run output is noise without a human to triage

## Args

```
--project <name>         optional  project scope (default: detected from cwd via git remote or CLAUDE.md)
--checks <csv>           optional  subset of verifiable claim types to run
                                   (default: linear-team-key,project-names,recent-tickets,file-paths)
--apply                  optional  write superseding observations for contradicted claims (default: dry-run)
```

## Supported claim types

| Check | What it verifies |
|---|---|
| `linear-team-key` | Any observation containing `team=<KEY>` or `team key: <KEY>` — verify against `list_teams` |
| `project-names` | Any observation containing `project=<NAME>` or `project: <NAME>` — verify against `list_projects` |
| `recent-tickets` | Any observation referencing `<KEY>-<NNN>` ticket IDs — verify the ticket still exists via `get_issue` |
| `file-paths` | Any observation containing absolute paths (`/home/...`, `~/...`) — verify path exists on disk |

## Procedure

### 1. Resolve project scope

- If `--project` given, use it directly.
- Otherwise, detect from `git remote get-url origin` (extract repo name) or read `CLAUDE.md` for project name.
- This determines the engram observation filter.

### 2. Fetch engram observations

- `mem raw "/search?q=project:<name>"` (or `mem_list project=<name>` if available).
- Collect all observations. If zero, emit "no observations found for project <name>" and exit 0.

### 3. Extract verifiable claims

For each observation body, run the claim-extraction regexes:

- **team key**: `\bteam[=:\s]+([A-Z]{2,6})\b` (e.g. `team=TOD`, `team: CER`)
- **project name**: `\bproject[=:\s]+"?([^"\n,]+)"?` (e.g. `project=unsigned-paas`)
- **ticket ID**: `\b([A-Z]{2,6}-\d+)\b` (e.g. `TOD-42`, `CER-7`)
- **file path**: `(/home/[^\s,]+|~/[^\s,]+)` (e.g. `/home/ctodie/.claude/settings.json`)

Build a list of `{obs_id, claim_type, claim_value, observation_snippet}` rows.

### 4. Verify each claim

- **linear-team-key**: `list_teams` → collect all `key` values. Claim is stale if the extracted key is not present.
- **project-names**: `list_projects` filtered to team → collect names. Claim is stale if the name is not present.
- **recent-tickets**: `get_issue(<id>)` — stale if 404 / not found. (Skip if ticket IDs are numerous; cap at 10 per run to avoid rate limits.)
- **file-paths**: `[ -e "<path>" ]` shell check. Stale if path does not exist.

### 5. Print the contradiction table

```
engram-drift-check: project=unsigned-paas  (3 observations scanned, 2 claims extracted)
──────────────────────────────────────────────────────────────────────────
  obs-id       claim                    ground-truth          verdict
──────────────────────────────────────────────────────────────────────────
  obs-abc123   team=TOD                 teams: CER, UNS, ...  STALE
  obs-def456   project=reverie-ai       not in list_projects  STALE
  obs-ghi789   team=CER                 teams: CER, UNS, ...  ok
──────────────────────────────────────────────────────────────────────────
2 stale claim(s). Re-run with --apply to write superseding observations.
```

If no contradictions: "engram-drift-check: all verifiable claims match ground truth."

### 6. Apply mode — write supersessions

If `--apply` and contradictions exist, for each stale claim:

1. Compose a superseding observation body:
   ```
   [drift-correction] <claim_type> was: "<stale_value>", verified: "<ground_truth_value>"
   Supersedes obs <obs_id>.
   project=<name> type=project-fact
   ```
2. `mem_save` the new observation (via `mcp__engram__save_observation` or `mem_save`).
3. If engram supports `superseded_by` metadata on the old observation, call `mem_update obs_id=<old_id> superseded_by=<new_id>`. Log a warning if not supported.
4. Report: `obs-abc123 superseded by <new-id>`.

### 7. Session-start integration

When invoked by `session-bootstrap-engram-drift.sh`:
- Always dry-run (never `--apply` from the hook).
- If contradictions found, format the output as a `<system-reminder>` block so it appears at the top of context:
  ```
  <system-reminder>
  engram-drift-check: 2 stale claim(s) detected for project=unsigned-paas.
    obs-abc123: team=TOD → actual team keys: CER, UNS
  Run /engram-drift-check --apply to correct.
  </system-reminder>
  ```
- If no contradictions, emit nothing (silent pass — don't pollute session start with green-light noise).

## Relationship to other skills

| Skill | Verb |
|---|---|
| `engram-drift-check` | read + verify + optional supersede |
| `engram:memory` | write new observations (the supersession write protocol) |
| `engram-audit` | structural audit of engram DB (schema, orphan links) |

Supersession writes use `engram:memory`'s write semantics — this skill does not bypass the protocol, it calls it.
