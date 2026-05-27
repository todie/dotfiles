---
name: spec-align
description: Build a coverage matrix between a spec markdown file and Linear tickets — for each H2 section, show whether a matching ticket exists, with what confidence, and what gaps remain. Read-only by default; `--file` pipes uncovered sections through `linear-file-spec` to create tickets. Use when the user says "spec coverage", "what's missing from Linear for this spec", "align spec to tickets", "coverage matrix for docs/foo.md". Args — `<spec-path>` required, `--team <key>` default TOD, `--project <name>` required, `--milestone <name>` optional scope, `--depth <H1|H2|H3>` default H2, `--file` to create tickets for gaps.
---

# spec-align — spec section ↔ Linear ticket coverage matrix

Walk a single spec document and a Linear scope; for each heading produce one row showing whether a tracking ticket exists, how confident the match is, and what gap remains. Default output is a printed coverage table with a gap list. No mutations unless `--file` is passed.

## When to use

- User says "spec coverage", "what's missing from Linear for this spec", "align spec to tickets", "coverage matrix for docs/foo.md", "which sections don't have tickets yet"
- After writing or updating a spec — verify the ticket backlog reflects the new sections before a planning session
- Before a milestone cut — confirm every spec section has a linked ticket with the right milestone

**Don't** use this when:
- The user wants cross-repo three-way drift (spec ↔ PR ↔ ticket) — use `canon-sync` for that
- The user wants to file tickets from a plan doc without checking existing coverage first — `linear-file-spec` is faster but won't dedupe against existing tickets
- Scope is unscoped (no `--project`) — refuse; whole-workspace scans produce misleading confidence scores

## Args

```
<spec-path>          required  path to a single markdown file (or glob of .md files)
--team <key>         optional  Linear team key (default: TOD)
--project <name>     required  Linear project to search for matching tickets
--milestone <name>   optional  narrow ticket search to this milestone
--depth <H1|H2|H3>  optional  which heading level counts as a "section" (default: H2)
--file               optional  after printing the gap table, pipe uncovered sections
                               through linear-file-spec to create tickets (off by default)
```

## Procedure

### 1. Parse and validate args

- Require `<spec-path>` and `--project`; refuse with a clear error if either is missing.
- Expand globs if a pattern is given; process files sequentially (one coverage table per file).
- Parse `--depth` to determine which heading level splits sections (default H2).

### 2. Slice the spec into sections

Use the same H2-splitter `linear-file-spec` uses: walk lines, emit a section record `{heading, body, line_range}` whenever a heading of the target depth is encountered. Body runs until the next heading of equal-or-higher depth.

### 3. Fetch Linear tickets in scope

- `list_teams` → confirm the team key exists.
- `list_projects` filter to `--project` name → get project ID.
- If `--milestone` given, `list_milestones` → get milestone ID.
- `list_issues` with team/project/milestone filters. Paginate until exhausted.

### 4. Build the match index

Construct a `{normalized-title → ticket}` map:
- Normalize: lowercase, strip punctuation, collapse whitespace.
- Also index the first line of each ticket's description body for spec-anchor strings.

### 5. Score each section

For each spec section, walk the match index in priority order:
1. **exact-title**: normalized section heading == normalized ticket title → confidence `exact`
2. **body-match**: normalized section heading appears in ticket description → confidence `body`
3. **inferred**: 3+ words of the section heading appear in the ticket title → confidence `inferred`
4. **none**: no match found → `gap`

If multiple tickets match at the same confidence level, list all of them (comma-separated in the table).

### 6. Print the coverage table

```
spec-align: <spec-path> × <project>
─────────────────────────────────────────────────────────────────
Section                          Ticket(s)        Confidence
─────────────────────────────────────────────────────────────────
## Overview                      TOD-42           exact
## Authentication flow           TOD-17, TOD-89   body
## GPU scheduling                —                gap
## Metrics export                TOD-55           inferred
─────────────────────────────────────────────────────────────────
Coverage: 3/4 sections matched (75%)

Gaps (1):
  ## GPU scheduling  [line 47]
```

### 7. Handle `--file` mode

If `--file` is passed and gaps exist:
- Emit a notice: "Filing N uncovered sections via linear-file-spec..."
- For each gap section, invoke `linear-file-spec` passing the section body as the spec fragment and the `--project`/`--milestone`/`--team` flags as-is.
- Respect `linear-file-spec`'s own rate-limit-aware batching and `# bulk-file-spec: skip` logic — do not re-implement.
- Report the filed ticket IDs alongside the gap rows in the final table.

Without `--file`, print a one-liner at the end: "Re-run with --file to create tickets for gaps."

## Matching heuristic notes

The fuzzy match is deliberately conservative: `inferred` requires 3+ content words (not stop-words), not just any 3 words. Stop-word list: a, an, the, and, or, of, for, to, in, with, via, using, how. This avoids false positives on generic headings like "## Overview and Background".

Levenshtein distance matching is explicitly deferred — exact and substring matching covers ~90% of real cases and avoids dependency pull.

## Relationship to other skills

| Skill | Verb | Scope |
|---|---|---|
| `spec-align` | spec → ticket coverage, optional file | one spec doc + one project |
| `linear-file-spec` | file tickets from spec sections | one spec doc, always files |
| `canon-sync` | three-way drift (spec ↔ PR ↔ ticket) | repo-wide, read-only default |

`spec-align` delegates filing to `linear-file-spec` rather than reimplementing it. `canon-sync`'s spec parser is the appropriate code to reuse for the heading splitter if these skills are ever refactored into a shared library.
