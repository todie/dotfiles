---
name: linear-groom
description: Audit a Linear scope (team / project / milestone) for ticket drift — stale, missing labels, missing estimate/assignee/project, orphan (no milestone), duplicate (exact + fuzzy) titles, broken relation mirrors — and propose a fix plan. Read-only by default; `--apply` writes the mechanical fixes in rate-limited batches with automatic `# bulk-file-spec: skip` injection when batch > 5. Always runs an OAuth preflight before any list/save call. Use when the user says "groom Linear", "audit the backlog", "clean up tickets in <project>", "find stale tickets". Args — optional `--team <key>` (default TOD), `--project <name>`, `--milestone <name>`, `--check <csv>` (default: all; includes relation-mirror), `--stale-days <N>` (default 14), `--apply`, `--auto-bulk-marker` (default on), `--batch <N>` (default 10), `--slack <channel>` to post the report, `--ai-suggest` to add a dry-run-only AI proposal pass for non-mechanical fields.
---

# linear-groom — bulk Linear audit + safe fix loop

Walk a Linear scope, surface every drift signal as a structured row, then either print the plan (default) or apply the fixes in rate-limited batches. The audit set is opinionated: stale tickets, missing labels, missing estimates, missing assignee, missing project, orphan-of-milestone, and duplicate titles. Everything else is out of scope — this is *grooming*, not arbitrary bulk edits.

## When to use

- User says "groom Linear", "audit the backlog", "what's stale in <project>", "clean up tickets", "find tickets missing labels/estimates"
- Before a planning session — pre-flight the backlog so the human time is spent on judgment, not enumeration
- Recurring weekly hygiene loop (pair with `/loop 7d /linear-groom --team TOD`)

**Don't** use this when:
- The user wants arbitrary bulk edits ("change priority of these 20 tickets to X") — that's a different shape; call `mcp__claude_ai_Linear__save_issue` directly in a loop
- The user wants to file new tickets — use `linear-file-spec` (multi-section) or `file-bug` (single)
- The user wants to delete or merge tickets — the MCP lacks delete, and merging is judgment-heavy; surface the candidates and let the user act in the UI
- Scope is unscoped ("audit all of Linear") — refuse and require at least `--team` or `--project`. Whole-workspace scans get rate-limited and the report is too long to be useful

## Procedure

### 1. Parse args

- `--team <key>`: Linear team key (default `TOD`)
- `--project <name>`: scope to one project (exact name match)
- `--milestone <name>`: scope to one milestone
- `--check <csv>`: subset of `stale,labels,estimate,assignee,project,orphan,duplicate,relation-mirror` (default: all)
- `--stale-days <N>`: stale threshold in days (default `14`)
- `--apply`: execute the fix plan; default is dry-run
- `--batch <N>`: max writes per second (default `10`)
- `--no-preflight`: skip the OAuth check (faster reruns; only use when you just ran it)
- `--slack <channel>`: after the report, post a summary (counts + manual-review table) to a Slack channel via `mcp__claude_ai_Slack__slack_send_message`. Channel name without `#`.
- `--ai-suggest`: add a third output section with AI-proposed values for non-mechanical fields (labels, estimate, project, milestone). Dry-run only — `--apply` never writes AI suggestions, even when both flags are passed.
- `--auto-bulk-marker` / `--no-auto-bulk-marker`: when the `--apply` loop writes more than 5 `save_issue` calls, auto-inject `# bulk-file-spec: skip` into each call's description field to stay under the Linear rate limit. Default: on. Disable only when you know the batch will stay under 5 or you are intentionally testing the rate-limit path.

If no scope flag is given and the user didn't supply one in the prompt, refuse with: `linear-groom requires --team, --project, or --milestone — refusing to audit all of Linear`.

### 2. OAuth + scope preflight

Run **one** cheap call: `mcp__claude_ai_Linear__list_teams` (no args).

- If it succeeds → OAuth is alive. Verify the resolved team key exists in the response; abort with a clear error if not.
- If it fails with an auth-shaped error → abort with: `Linear OAuth expired. Re-auth with: /mcp` and stop. Do **not** retry, do **not** continue with the next check.

Then resolve `--project` and `--milestone` to IDs via `list_projects` / `list_milestones` if provided. Abort if a name doesn't match exactly.

Print a one-line preflight summary before any other work:
```
Preflight: team=TOD (ok) · project=Reverie (ok) · milestone=Phase 5 (ok) · checks=all · mode=dry-run
```

### 3. List tickets in scope

Use `mcp__claude_ai_Linear__list_issues` with the resolved filters. Page through if needed (the MCP returns up to ~50 per page).

State filter: only open tickets (Backlog, Todo, In Progress, In Review) — closed/cancelled tickets aren't drift candidates. Hard-code this; do not expose as a flag.

Cap at 200 tickets per scope. If the scope returns more, abort with: `Scope returned >200 tickets — narrow with --milestone or --project before grooming` — the report becomes unactionable past that size.

### 4. Run checks

For each enabled check, walk the ticket list once and tag each ticket with the drift signals it triggers. A ticket can trigger multiple.

- **stale**: `updatedAt` older than `--stale-days` days AND state is not `Backlog`. (Backlog is *meant* to be stale; In Progress that hasn't moved in 14d is the real signal.)
- **labels**: `labels` array is empty
- **estimate**: `estimate` is null AND state is not `Backlog` (backlog tickets routinely lack estimates)
- **assignee**: `assignee` is null AND state is `In Progress` or `In Review` (unassigned active work is the smell; unassigned backlog is fine)
- **project**: `project` is null AND `--team` scope (not `--project` — that's tautological)
- **orphan**: `milestone` is null AND ticket is in a project that has milestones
- **duplicate**: two or more tickets whose titles match either (a) exact normalized form (lowercase, trimmed, whitespace-collapsed) or (b) Levenshtein-similarity ≥ 0.85 on the normalized form AND in the same project. Surface as a *pair* (or cluster) row, not per-ticket. Tag each pair with `exact` or `fuzzy:<score>` so the manual reviewer can prioritize the cheap merges. Fuzzy matching is O(n²); the 200-ticket scope cap keeps this at ≤ 40k comparisons (fast). No downgrade in normal operation. Future-extension territory: switch to embeddings if anyone ever raises the scope cap.
- **relation-mirror**: for each ticket whose `blocks` or `blockedBy` relation array is non-empty, call `get_issue(id, includeRelations: true)` on the *downstream* ticket and assert the mirror edge exists. A missing mirror means Linear's relation graph is asymmetric — surfaced as `relation-mirror-broken` in the manual-review table. This check is read-only and never auto-fixed; the user must correct the relation in the UI or via a manual `save_issue`. Implements the validation pass from `feedback_linear_deps_bidirectional.md`. Note: this check adds one `get_issue` call per ticket with relations — it is rate-limited to 20 such calls per groom run to avoid burst. If the scope has more than 20 tickets with relations, the check runs on the first 20 and appends a warning: `relation-mirror check capped at 20 — re-run with --milestone to narrow scope`.

### 5. Build the fix plan

For each drift signal, propose a fix *only when the fix is mechanical*:

| Signal | Auto-fixable? | Proposed action |
|---|---|---|
| stale | No | Report only — human picks: nudge, reassign, close |
| labels | No | Report only — labels need judgment |
| estimate | No | Report only |
| assignee | No | Report only |
| project | Sometimes | If the team has exactly one active project, propose attach. Else report only. |
| orphan | No | Report only — milestone choice needs judgment |
| duplicate | No | Report only — surface both IDs for human merge in UI |

**This skill does not auto-fix anything that requires judgment.** The `--apply` path only writes the *mechanical* fixes (currently: project attach when unambiguous). Everything else goes in the report under "Manual review needed".

### 6. Dry-run output (default)

Print two markdown tables:

**Auto-fixable**:
| ID | Title | Signal | Proposed fix |
|----|-------|--------|--------------|
| TOD-501 | Wire mesh telemetry | project missing | attach to project "Reverie" |

**Manual review needed**:
| ID | Title | Signals | Last updated |
|----|-------|---------|--------------|
| TOD-487 | Investigate flaky test | stale, no-labels, no-estimate | 2026-04-10 |
| TOD-491 | Investigate flaky test | duplicate-of TOD-487 | 2026-04-22 |

Then a summary line: `N tickets scanned, K auto-fixable, M manual. Re-run with --apply to write the K auto-fixes.`

### 6b. AI-suggest pass (if `--ai-suggest`)

Append a third table — **AI-proposed (review only — never auto-applied)**:

| ID | Title | Field | Current | Proposed | Confidence |
|----|-------|-------|---------|----------|------------|
| TOD-487 | Investigate flaky e2e | labels | — | `[bug, e2e, mesh]` | high |
| TOD-487 | Investigate flaky e2e | estimate | — | 3 | medium |

How to generate: spawn one `general-purpose` Agent with the manual-review rows + the ticket bodies (fetched via `mcp__claude_ai_Linear__get_issue`), and ask it to propose values for empty fields based on the ticket text. Limit to ≤ 25 tickets per AI call to keep the prompt tight; if more rows exist, page through.

**Cost gate:** cap the total tickets sent through the AI pass at 100. If manual-review > 100, refuse with `--ai-suggest exceeds 100-ticket budget; narrow with --milestone or --check`. AI passes burn real tokens; the user should be deliberate about scope.

Confidence label: the subagent reports `high|medium|low` per suggestion based on how clearly the ticket body implies the value. Surface low-confidence suggestions in a grey-italic style note rather than the main table if your terminal renderer supports it.

This pass costs real tokens — only run when explicitly requested.

### 6c. Slack post (if `--slack <channel>`)

After printing the report locally, post a summary via `mcp__claude_ai_Slack__slack_send_message`:

- Channel: the value passed to `--slack` (strip leading `#` if present)
- Body: one-line scope header + counts (e.g. `47 scanned · 1 auto-fixable · 3 manual review`) + the manual-review table only (collapsed in a Slack code block). Skip the auto-fixable table — that's actionable terminal work, not async team review. Skip the AI-suggest table — too noisy for a channel.
- If the manual-review table exceeds 30 rows, post a header + counts only and attach the full table as a snippet via the Slack snippet upload flow (or fall back to a truncated table with `…N more` if snippet upload is unavailable).

On Slack post failure: log it, but do not fail the overall command — the local report is the source of truth.

Exit. Do not call `save_issue`.

### 7. Apply mode (`--apply`)

Only acts on the auto-fixable rows. For each row:

- If the planned batch size exceeds 5 and `--auto-bulk-marker` is on (default), inject `# bulk-file-spec: skip` as a trailing line in the `description` field of every `save_issue` call in this run. Log once: `auto-bulk-marker: injecting # bulk-file-spec: skip (N writes > 5-call threshold)`.
- Call `mcp__claude_ai_Linear__save_issue` with `id` + the single field being changed (e.g. `project: <id>`).
- Sequential, not parallel. Sleep `1000 / batch` ms between calls (default 100ms → 10/sec).
- On rate-limit error (HTTP 429 or MCP-level rate-limit shape): exponential backoff starting at 2s, doubling each retry, max 5 retries. After 5 → abort the apply loop and report what landed.
- On any other error: abort the apply loop immediately, report what landed, surface the error.

After the loop, print the final tally:
```
Applied: 7 fixes, 0 failures, 0 rate-limit retries
Manual review still needed: 23 tickets
```

### 8. Exit

Return cleanly. Do NOT auto-loop into another scope. If the user wants weekly grooming, they wrap it in `/loop`.

## Safety invariants

- **Always** run the OAuth preflight first. Discovering the token is dead mid-batch is the #1 friction from your usage report.
- **Always** require an explicit scope. Whole-workspace audits don't fit on a screen and burn rate-limit budget.
- **Never** auto-fix anything beyond the mechanical fixes listed in step 5. Adding labels, estimates, assignees, or milestones requires human judgment — surface, don't decide.
- **Never** delete or close tickets. The MCP can't delete; closing is a judgment call.
- **Never** call `save_issue` in parallel. Sequential + rate-limit backoff is the only safe write pattern given the OAuth + rate-limit history.
- **Never** continue after an auth error. Surface the `/mcp` reauth and stop.
- **Never** auto-apply an `--ai-suggest` proposal, even if the user also passed `--apply`. AI-proposed fields require human review by design; the flags compose as "apply mechanical fixes AND propose AI ones for review", not "apply both".
- **Always** print the resolved scope before doing anything — the wrong-workspace bug from your insights report is one user typo away.

## Example invocation

```
linear-groom --team TOD --project Reverie --stale-days 21
```

Expected dry-run output:

```
Preflight: team=TOD (ok) · project=Reverie (ok) · milestone=— · checks=all · mode=dry-run

Auto-fixable:
| ID      | Title                    | Signal          | Proposed fix             |
|---------|--------------------------|-----------------|--------------------------|
| TOD-512 | Wire mesh telemetry hook | project missing | attach to "Reverie" (sole active project) |

Manual review needed:
| ID      | Title                       | Signals                              | Last updated |
|---------|-----------------------------|--------------------------------------|--------------|
| TOD-487 | Investigate flaky e2e       | stale (37d), no-labels, no-estimate  | 2026-04-20   |
| TOD-491 | Investigate flaky e2e       | duplicate-of TOD-487                 | 2026-04-22   |
| TOD-503 | Refactor offload router     | stale (22d), no-assignee             | 2026-05-05   |

47 tickets scanned, 1 auto-fixable, 3 manual. Re-run with --apply to write the 1 auto-fix.
```

After `--apply`:

```
Applied: 1 fix, 0 failures, 0 rate-limit retries
Manual review still needed: 3 tickets
```

## Future extensions

- `--export <path>`: dump the manual-review table to a markdown file so the user can triage offline
- `--since <date>`: restrict the scan to tickets touched after a date (faster on large projects)
- `--cron <interval>`: register a recurring `CronCreate` rather than punt to `/loop`
- A `--seed` flag to make the duplicate-pair surfacing deterministic across runs (matters when fuzzy matching ties)
- Semantic duplicate detection via embeddings (current fuzzy match is Levenshtein-only; embeddings catch reword/paraphrase duplicates)
- Raise the `relation-mirror` cap above 20 if the Linear MCP adds a batch-get endpoint (currently one `get_issue` per ticket is the only option)
