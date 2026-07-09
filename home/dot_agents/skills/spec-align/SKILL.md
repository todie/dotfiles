---
name: spec-align
description: Build a section-by-section coverage matrix between a markdown spec file and the Linear tickets in a given scope (team / project / milestone), surfacing which sections have a matching ticket, which don't, and the confidence of each match. Read-only by default; with `--file`, hands the uncovered-section list off to `linear-file-spec` to create the missing tickets (rate-limit + dependency wiring reused, not re-implemented). Use when the user says "spec coverage", "what's missing from Linear for this spec", "align spec to tickets", "coverage matrix for docs/foo.md". Args — required `<spec-path>`, required `--project <name>`, optional `--team <key>` (default TOD), `--milestone <name>`, `--depth <H1|H2|H3>` (default H2), `--file`.
---

# spec-align — spec ↔ Linear ticket coverage matrix

Parse a markdown spec into sections (using the same H2-splitter `linear-file-spec` uses), pull the Linear tickets in a given scope, and emit a coverage matrix: which sections have a ticket, which don't, and how confident the match is. Read-only by default — the goal is to surface the gap, not file. With `--file`, the uncovered sections are piped into `linear-file-spec` so we don't duplicate its rate-limit + dependency wiring code.

## When to use

- User says "spec coverage", "align spec to tickets", "what's missing from Linear for this doc", "coverage matrix for docs/foo.md"
- After a planning doc lands and the user wants to know whether the backlog reflects it
- Before a milestone close-out, to confirm every section in the spec has a tracked ticket
- As a complement to `canon-sync` when you want spec-driven (not repo-wide) coverage scoped to one doc

**Don't** use this when:
- The user just wants to file the whole spec — that's `linear-file-spec` directly, no alignment needed
- The spec has no clear section structure (no `## ...` headers at the chosen depth) — refuse and ask the user to add headers or call `linear-file-spec` with the whole body
- The Linear scope is unscoped (no `--project`) — refuse, the whole-workspace match set is unactionable
- The spec is a chat transcript or rant — there's no section ↔ ticket mapping to build

## Procedure

### 1. Parse args

- First positional arg: path to the spec file (required, must exist)
- `--project <name>`: required, exact name match against `list_projects`
- `--team <key>`: default `TOD`
- `--milestone <name>`: optional further narrowing of the Linear scope
- `--depth <H1|H2|H3>`: which heading level counts as a "section" (default `H2`)
- `--file`: after the coverage report, hand the uncovered sections to `linear-file-spec` to create tickets. Off by default — the default mode is surface-only.

If `--project` is missing, refuse with: `spec-align requires --project — refusing to align against all of Linear`.

### 2. Read the spec file

Use the Read tool. If the file doesn't exist, abort. Capture the line count.

**Safety gate:** if `wc -l` > 1000, warn before proceeding — large specs can produce dozens of sections and a noisy report. Continue, but log the warning.

### 3. OAuth + scope preflight

Run one cheap call: `mcp__claude_ai_Linear__list_teams`.

- If it succeeds → OAuth is alive. Verify the resolved team key exists.
- If it fails with an auth-shaped error → abort with: `Linear OAuth expired. Re-auth with: /mcp` and stop.

Resolve `--project` (and `--milestone` if given) to IDs via `list_projects` / `list_milestones`. Abort if a name doesn't match exactly.

Print a one-line preflight summary:
```
Preflight: team=TOD (ok) · project=Reverie (ok) · milestone=Phase 5 (ok) · depth=H2 · mode=report-only
```

### 4. Parse spec sections

Walk the spec body and split on the chosen `--depth` heading level (default H2 — `## ...`). Accept the same header styles `linear-file-spec` does:

- **Lettered**: `## Part A: <title>`, `## Part B: <title>`
- **Numbered**: `## 1. <title>`, `## 2. <title>`
- **Plain**: `## <title>` (no prefix marker — title is the whole text after `##`)

For each section, capture:

- **Heading text** (raw, post-marker — e.g. `capability handshake schema`)
- **Normalized title**: lowercase, trim, collapse whitespace, strip trailing punctuation. This is the key for the title-match heuristic.
- **First-line-of-body**: first non-blank line under the heading, capped at 240 chars. Used for the body-grep heuristic.
- **Line range**: `(start_line, end_line)` for the report

Skip frontmatter (`---` ... `---` block at file head) and the preamble (text between frontmatter and the first matching heading) — only the sections at the chosen depth contribute rows.

If zero sections were found, abort with: `No sections at depth=<depth> in <spec-path>. Try a different --depth or check the heading style.`

### 5. List Linear tickets in scope

Use `mcp__claude_ai_Linear__list_issues` with the resolved filters (team + project, plus milestone if given). Page through if needed. State filter: include all open + recently closed (Backlog, Todo, In Progress, In Review, Done within the last 60 days). Closed-long-ago tickets aren't drift candidates — they're history.

Cap at 300 tickets in scope. If more, abort with: `Scope returned >300 tickets — narrow with --milestone before aligning` — the matrix becomes unactionable past that size.

Build two indexes for the match pass:

- `title_index`: `{normalized_title → [ticket, ...]}` — collisions are kept as a list (rare but possible).
- `body_corpus`: `{ticket_id → (title, description_snippet)}` where `description_snippet` is the first ~500 chars of the ticket description, lowercased. Used for the body-match heuristic.

### 6. Match sections to tickets

For each spec section, attempt to match in this priority order. Stop at the first hit.

1. **exact-title** — `title_index[section.normalized]` returns one or more tickets. Confidence: `exact`.
2. **body-match** — search `body_corpus` for a substring match on the section's first-line-of-body (after lowercasing and stripping markdown formatting like `**bold**` markers). If exactly one ticket's body snippet contains the phrase, that's the match. Confidence: `body-match`. If multiple tickets match the same phrase, surface all of them but mark the row `inferred-multi` and let the user disambiguate.
3. **inferred** — Levenshtein-similarity ≥ 0.80 on the normalized title against the title index. Confidence: `inferred:<score>`. Defer this heuristic — start the skill without it and only add if the first two heuristics leave too many false-negative gaps in practice. Document its absence in the report footer when not yet implemented.
4. **none** — no match. Confidence: `none`. This section is a *gap*.

The Levenshtein pass is O(sections × tickets) — at the 300-ticket / 50-section cap that's 15k comparisons, fast enough. Skip if the previous two heuristics already matched the section.

### 7. Build the coverage matrix

Print one markdown table:

| # | Section | Matched ticket(s) | Confidence | Spec lines |
|---|---------|-------------------|------------|-----------:|
| 1 | capability handshake schema | TOD-481 | exact | 14–62 |
| 2 | protobuf wire migration | TOD-482 | body-match | 64–118 |
| 3 | server runtime | — | none | 220–284 |
| 4 | metrics export | TOD-487, TOD-489 | inferred-multi | 286–340 |

Then a one-line coverage summary:

```
Coverage: 3/4 sections have a ticket (75%) · 1 gap · 1 multi-match needs review
```

And a separate **Gaps** table (for the `--file` handoff):

| # | Section | Spec lines | Preview |
|---|---------|-----------:|---------|
| 3 | server runtime | 220–284 | The server runtime is responsible for accepting capability... |

### 8. `--file` mode (optional)

When `--file` is set and at least one section has confidence `none`, build an inline spec stub containing only the uncovered sections (preserving their heading + body verbatim from the source spec) and hand it to `linear-file-spec` via a recursive skill invocation, *not* by re-implementing the file logic.

The handoff stub looks like:

```markdown
---
project: <resolved project name>
team: <resolved team>
milestone: <resolved milestone or omit>
labels: <inherited or empty>
---

# Auto-filed gaps from spec-align: <original spec basename>

Source spec: <absolute path>

## <section heading 1 — exactly as it appeared in source>
**priority**: Medium
**blocked-by**: (none)

<verbatim section body>

## <section heading 2 — exactly as it appeared in source>
...
```

Write that stub to `/tmp/spec-align-gaps-<unix-ts>.md` and call:

```
linear-file-spec /tmp/spec-align-gaps-<ts>.md --dry-run
```

Always start with `--dry-run` — `linear-file-spec` itself prints the planned tickets and the user confirms before the actual filing. Do not auto-drop the `--dry-run` flag; the user must re-invoke without it. Print the exact follow-up command for the user to copy.

**Priority and blocked-by inference:** spec-align cannot infer these from a section header alone. Default every gap to `priority: Medium` and `blocked-by: (none)`. The user edits the stub before re-running without `--dry-run` if they want different values.

### 9. Exit

Return cleanly. Do NOT recursively invoke `spec-align` on other specs in the directory — one spec per invocation. If the user wants directory-wide coverage, they run the skill once per file (or use `--file <glob>`, future extension).

## Safety invariants

- **Always** run the OAuth preflight first. Discovering the token is dead after parsing the spec wastes work.
- **Always** require `--project`. Whole-workspace alignment is meaningless.
- **Never** auto-file tickets without going through `linear-file-spec` — that skill owns the rate-limit and dependency-wiring logic, and duplicating it here is how those bugs come back.
- **Never** drop the `--dry-run` flag in the `--file` handoff. The user must explicitly re-run to file.
- **Never** invent matches. If two heuristics fail, the section is a `none` — that's the whole point of the coverage matrix.
- **Always** print the resolved scope before the matrix — wrong-project alignment is a one-typo bug.
- **Never** mutate Linear tickets in this skill. Even when `--file` is set, the only writes go through `linear-file-spec`.

## Example invocation

```
spec-align /tmp/capabilities-protocol-spec-v0.md --project Reverie --milestone "Phase 5: Auto-Capture & Write-Gate"
```

Expected output:

```
Preflight: team=TOD (ok) · project=Reverie (ok) · milestone=Phase 5: Auto-Capture & Write-Gate (ok) · depth=H2 · mode=report-only

Coverage matrix:
| # | Section                       | Matched ticket(s) | Confidence  | Spec lines |
|---|-------------------------------|-------------------|-------------|-----------:|
| 1 | capability handshake schema   | TOD-481           | exact       | 14–62      |
| 2 | protobuf wire migration       | TOD-482           | body-match  | 64–118     |
| 3 | wire format                   | TOD-483           | exact       | 120–166    |
| 4 | server runtime                | —                 | none        | 168–224    |
| 5 | client SDK                    | —                 | none        | 226–280    |

Coverage: 3/5 sections have a ticket (60%) · 2 gaps · 0 multi-match

Gaps:
| # | Section        | Spec lines  | Preview                                                           |
|---|----------------|-------------|-------------------------------------------------------------------|
| 4 | server runtime | 168–224     | The server runtime is responsible for accepting capability...     |
| 5 | client SDK     | 226–280     | The client SDK exposes a Capabilities trait that peer sessions...|

Re-run with --file to stage the 2 gaps as a linear-file-spec dry-run.
```

With `--file`:

```
... (matrix as above) ...

Wrote gap stub: /tmp/spec-align-gaps-1748400000.md (2 sections)
Run to file the gaps:
  linear-file-spec /tmp/spec-align-gaps-1748400000.md
(or with --dry-run first to preview the tickets)
```

## Future extensions

- **`--file <glob>`** to align across multiple specs in one invocation, emitting one matrix per file
- **`--strict`** to exit non-zero when coverage < 100% (for CI use; pair with `canon-sync --ci`)
- **`--depth H3`** sub-section support: today only one depth is matched per run; future versions could surface nested coverage (H2 has ticket but its H3 children don't)
- **Embedding-based match** for the `inferred` confidence band — Levenshtein misses paraphrased section titles
- **Tighter integration with `canon-sync`**: spec-align could feed its gap rows into canon-sync's `spec_section_no_ticket` check so the warning surfaces in both tools
- **Cycle the priority inference** from a `**priority**:` line if the spec section already has one in `linear-file-spec` style — currently the `--file` stub defaults to `Medium` even when the source spec specified `High`
