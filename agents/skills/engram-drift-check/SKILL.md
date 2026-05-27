---
name: engram-drift-check
description: Diff session-start engram observations against ground truth — Linear team keys, project names, ticket IDs, and file paths parsed from observations are verified against `mcp__claude_ai_Linear__list_teams` / `list_projects` and the local filesystem. Read-only by default; `--apply` writes a superseding observation (via `mcp__plugin_engram_engram__mem_update` with a `supersedes:` field) referencing the stale one's ID. Catches the unsigned-paas "team=TOD vs team=CER" drift bug. Use when the user says "is my engram memory current", "check memory for stale facts", "engram drift", or run automatically at session start. Args — `--project <name>` (default detected from cwd), `--checks <csv>` (default `linear-team-key,project-names,recent-tickets,file-paths`), `--apply` (writes supersession), `--limit <N>` (default 50 observations scanned per project), `--quiet` (suppress the per-check trace, only print the contradiction table).
allowed-tools:
  - Bash
  - Read
tags: [engram, memory, drift, audit, supersession]
---

# engram-drift-check — verify engram observations against ground truth

Pull every "factual" observation for a project, parse it for verifiable entities (Linear team keys, project names, ticket IDs, file paths), and check each one against the live source of truth. Surface contradictions as a table. Optionally write a superseding observation that records the correction with a back-reference to the stale obs.

Catches the failure mode from the 2026-05-27 unsigned-paas session: an engram observation claimed `team=TOD` for the unsigned-paas project when ground truth was `team=CER`, and Claude operated on the stale claim for several turns before the user caught it. Observations accrete without invalidation — this skill is the invalidation pass.

## When to use

- User says "engram drift", "is my memory current", "check engram for stale facts", "verify what I remember about this project"
- Session-start health check (paired with `session-bootstrap.sh` — see proposal section 4.3)
- After a Linear reorg (team renamed, project moved, milestone renumbered) when prior observations are stale by definition
- After a file rename or directory restructure when path-bearing observations may dangle

**Don't** use this when:
- Engram observations don't exist for the project — `mem stats` shows zero obs. Nothing to drift-check.
- The user wants a full engram health audit — that's `/engram-audit` (DB-level structural check). This skill is *semantic* drift, not structural.
- Linear OAuth is dead — the verifier needs `list_teams`/`list_projects` to do its job. Abort cleanly rather than mark every claim "unverifiable".
- The user wants to delete observations — this skill only supersedes, never hard-deletes. For hard delete use `/engram-cleanup`.

## Procedure

### 1. Parse args

- `--project <name>`: project filter (default: detect from `$(basename "$PWD")` — e.g. cwd `/home/ctodie/projects/unsigned-paas` → `unsigned-paas`)
- `--checks <csv>`: subset of `linear-team-key,project-names,recent-tickets,file-paths` (default: all)
- `--limit <N>`: max observations to scan per project (default 50; the most recent N)
- `--apply`: write superseding observations for each contradiction. Default is dry-run.
- `--quiet`: suppress per-observation trace lines; print only the final contradiction table.

### 2. Preflight

Confirm reveried is up:

```bash
curl -sf http://127.0.0.1:7437/health >/dev/null || { echo "reveried not running on :7437 — abort"; exit 1; }
```

Confirm Linear OAuth is alive by calling `mcp__claude_ai_Linear__list_teams`. If it errors with an auth-shaped message, abort with: `Linear OAuth expired. Re-auth with: /mcp` and stop. Cache the resulting `{key → name}` map for the team-key check.

Resolve project name. If `--project` was passed, use it verbatim. Otherwise:

```bash
PROJECT="${MEM_PROJECT:-$(basename "$PWD")}"
```

### 3. Pull observations

Use the `mem` CLI for the read path (the local helper that wraps reveried's HTTP API directly — faster than the MCP roundtrip and works without Linear OAuth):

```bash
mem raw "/observations/recent?project=${PROJECT}&limit=${LIMIT}"
```

Parse the JSON array. For each observation, capture: `id`, `type`, `title`, `content`, `topic_key`, `created_at`.

Filter to "factual" types. Default set: `feedback`, `project-fact`, `decision`, `convention`. Other types (e.g. `session-note`, `bench-run`) are too noisy and rarely contain verifiable claims — skip them.

If the filtered set is empty, print `No factual observations found for project=<name>. Nothing to drift-check.` and exit 0.

### 4. Parse claims out of content

For each filtered observation, run the enabled checks against `title + content`. Each check is a tight regex; broad NLP is out of scope.

**`linear-team-key`** — match `team\s*[:=]\s*([A-Z]{2,4})` and `\b([A-Z]{2,4})-\d+\b` (the second one captures bare ticket IDs like `TOD-123` whose prefix is implicitly the team key). For each captured team key, verify against the cached team map from step 2. If the key is not in the map, flag as `unknown-team`. If the key is in the map but the observation's context (the project name, the surrounding sentence) suggests a different team should own this project, flag as `wrong-team`.

To detect the "wrong-team" case specifically: if the project filter is `unsigned-paas` and the observation claims `team=TOD`, but `list_projects(team=TOD)` does NOT return a project named `unsigned-paas` while `list_projects(team=CER)` DOES, that's wrong-team drift. Cache `list_projects` results per team to avoid re-fetching.

**`project-names`** — match `project\s*[:=]\s*"?([A-Za-z][\w\s-]+)"?` and capture quoted project names like `"Reverie"`, `"unsigned-paas"`. Verify each via the cached `list_projects` calls. Flag `unknown-project` if no team has that project.

**`recent-tickets`** — match `\b([A-Z]{2,4})-(\d+)\b` for ticket IDs. For each unique `(team, number)`, call `mcp__claude_ai_Linear__get_issue` and confirm it exists. Cap at 10 lookups per run (rate-limit safety); if the observation set has more than 10 unique tickets, sample the 10 most recent and append a warning. Flag `missing-ticket` if the lookup returns not-found.

**`file-paths`** — match `(?<![A-Za-z0-9_])(/|~/)([A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8})` for absolute or home-relative paths with a file extension. Expand `~/` to `/home/ctodie/`. Check each path with `[ -e "$path" ]`. Flag `missing-file` if the path doesn't exist on disk.

### 5. Build the contradiction table

For each flagged claim, capture a row:

| obs id | type | claim | flag | ground truth | source URL |
|---|---|---|---|---|---|

- `obs id`: the engram observation id (also clickable as `http://127.0.0.1:7437/observations/<id>` for the user to inspect)
- `type`: from the observation
- `claim`: the captured substring (e.g. `team=TOD`)
- `flag`: `unknown-team` / `wrong-team` / `unknown-project` / `missing-ticket` / `missing-file`
- `ground truth`: what the live source says (e.g. `team=CER owns unsigned-paas`)
- `source URL`: link to the live source (Linear ticket URL, or `(filesystem)` for path checks)

If `--quiet` was not set, also emit a per-observation trace line as each one is processed:

```
[obs 9c4d3a1f] type=feedback (1/12)
  claim: team=TOD
  flag:  wrong-team (CER owns unsigned-paas)
```

### 6. Print the report

After all observations are scanned, print:

1. A one-line summary: `Scanned N obs in project=<name>. Found M contradictions across K observations.`
2. The contradiction table from step 5.
3. If `--apply` was NOT set: `Dry-run — no supersessions written. Re-run with --apply to record corrections.`

Exit 0 if no contradictions, exit 1 if any (so the skill can be wired into a CI / session-start gate that should fail loudly).

### 7. Apply mode — write supersessions

When `--apply` is set, for each contradiction:

1. Compose a corrected observation body. Example:

   ```
   Correction: <original claim> is stale. Ground truth: <verified value>.

   Verified <YYYY-MM-DD> via mcp__claude_ai_Linear__list_projects.
   Supersedes engram observation <original-id> (created <original-created-at>).
   ```

2. Call `mcp__plugin_engram_engram__mem_update` with:
   - `id`: the stale observation's id
   - `content`: the corrected body (above)
   - `supersedes`: the stale observation's id
   - `type`: same as the original
   - `title`: prefix with `[corrected] ` followed by the original title

   Note: engram's supersession semantics are documented in the `engram:memory` skill — the `supersedes:` field is the load-bearing piece. The MCP server resolves the back-link (sets the original's `superseded_by`) automatically.

3. Rate-limit: sequential calls, no parallelism. Engram local writes are fast (<50ms) but the MCP roundtrip plus reveried's WAL fsync can serialize poorly under burst.

4. Print one line per applied correction:

   ```
   Superseded obs 9c4d3a1f → new obs 7e8b2c44 ([corrected] unsigned-paas project facts)
   ```

5. Final summary: `Wrote N supersessions. Original observations remain in DB but are marked superseded.`

### 8. Optional: trigger downstream checks

After the report, suggest follow-ups if any contradictions landed:

- `>5 missing-file flags` → suggest the user ran a recent directory restructure, recommend `/canon-sync --check spec_section_no_ticket` to catch related drift
- `>0 wrong-team flags` → recommend rerunning the session-bootstrap context injection so subsequent turns operate on the corrected facts
- `>0 missing-ticket flags` → recommend `/linear-groom --team <key>` on the affected team to surface any related stale state

These are *suggestions* in the report footer, not auto-invocations.

## Safety invariants

- **Never** hard-delete a stale observation — always supersede. The original obs must remain queryable for audit purposes.
- **Never** write a supersession in dry-run mode. The `--apply` flag is the only path to mutation.
- **Never** parse claims with broad NLP — the regex set is intentionally tight. Better to miss a claim than to flag a non-claim and write a spurious supersession.
- **Never** trust the team-key prefix of a bare ticket ID (`TOD-123`) as ground truth on its own — the prefix is a *claim*, not a verification. Verify the team key against `list_teams` and the project ownership against `list_projects(team=<key>)`.
- **Never** call `get_issue` more than 10 times per run for the `recent-tickets` check. The cap keeps the run latency bounded and the Linear rate-limit safe.
- **Always** include the original observation id in the superseding observation's body — the audit trail is the entire point of the supersession protocol.
- **Always** exit 1 on contradiction-found so the skill can gate a CI or session-start hook.

## Example invocation

Dry-run on the current project:

```
engram-drift-check
```

Expected output shape:

```
Project:    unsigned-paas (detected from cwd)
Checks:     linear-team-key, project-names, recent-tickets, file-paths
Mode:       dry-run

Preflight:
  reveried     :7437 ok
  Linear OAuth ok (12 teams cached)

Scanning 12 factual observations (out of 47 total) for project=unsigned-paas...

[obs 9c4d3a1f] type=feedback (1/12)
  claim: team=TOD
  flag:  wrong-team (CER owns unsigned-paas)

[obs 7a2b8d5e] type=project-fact (3/12)
  claim: TOD-823
  flag:  missing-ticket (no such issue in TOD)

Scanned 12 obs in project=unsigned-paas. Found 2 contradictions across 2 observations.

| obs id     | type         | claim    | flag             | ground truth                | source URL                          |
|------------|--------------|----------|------------------|-----------------------------|-------------------------------------|
| 9c4d3a1f   | feedback     | team=TOD | wrong-team       | CER owns unsigned-paas      | https://linear.app/todie/team/CER   |
| 7a2b8d5e   | project-fact | TOD-823  | missing-ticket   | not found in TOD            | (no URL)                            |

Dry-run — no supersessions written. Re-run with --apply to record corrections.

Suggested follow-ups:
  /linear-groom --team CER   (rerun grooming on the correct team for this project)
```

With `--apply`:

```
engram-drift-check --apply
```

Adds at the end:

```
Superseded obs 9c4d3a1f → new obs 7e8b2c44 ([corrected] unsigned-paas project facts)
Superseded obs 7a2b8d5e → new obs 8f1d3b91 ([corrected] TOD-823 reference)

Wrote 2 supersessions. Original observations remain in DB but are marked superseded.
```

Scoped to a single check:

```
engram-drift-check --checks linear-team-key --project unsigned-paas --quiet
```

## Future extensions

- **`--strict`** — also fail on `unknown-team` / `unknown-project`, not just outright contradictions. Useful for catching observations made before a team / project existed (now-orphaned).
- **`--since <date>`** — only scan observations created after a given timestamp. Useful when a recent Linear reorg invalidates only the newest observations.
- **Levenshtein-distance project-name match** — currently exact-match only. A claim of `project=unsignedpaas` (no dash) should flag as a likely fuzzy match for `unsigned-paas`. Defer until first false-negative.
- **`--auto-supersede-similar`** — when two observations make the same correctable claim, supersede both with a single corrected obs rather than two separate supersessions. Avoids supersession-chain bloat on repeated claims.
- **Cross-project link verification** — when an observation references both `project=X` and `team=Y`, verify that team Y actually owns project X via `list_projects(team=Y)`. Currently checked indirectly via the wrong-team flag; could be promoted to its own check name.
- **Markdown report mode** (`--md`) — emit the contradiction table as a standalone `.md` file under `/tmp/engram-drift-<timestamp>.md` for posting into a Linear ticket or Slack channel as evidence.
