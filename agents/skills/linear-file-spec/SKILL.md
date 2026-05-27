---
name: linear-file-spec
description: Parse a multi-section markdown spec file into N linked Linear tickets via the claude_ai_Linear MCP. Extracts YAML frontmatter for project/team/milestone/labels, splits the body on `## Part X:` or `## N.` section headers, files one ticket per section in a first pass, then wires `blockedBy` and `relatedTo` dependencies in a second pass. Use when the user says "file the spec as tickets", "split this into Linear tickets", or pastes a multi-part proposal. Args — required `<spec-path>`, optional `--project`, `--team`, `--milestone`, `--labels`, `--dry-run`.
---

# linear-file-spec — markdown spec to linked Linear tickets

Parse a staged markdown spec file (typically in `/tmp/`) into N Linear tickets, one per top-level "Part" section, then wire the dependency graph between them. Eliminates the manual copy-paste loop of filing multi-part proposals where Part B blocks on Part A and so on.

## When to use

- User says "file this as Linear tickets", "split this spec into tickets", "make tickets from this proposal", or pastes a multi-part design doc and asks for it to be filed
- A spec in `/tmp/` has 2+ clearly numbered or lettered sections that should each be their own unit of work
- After writing a multi-part protocol spec where the parts have a dependency order (A blocks B blocks C)

**Don't** use this when:
- The spec has only one logical unit — call `mcp__claude_ai_Linear__save_issue` directly, the overhead doesn't pay off
- The section structure is ambiguous (no clear `## Part X:` or `## N.` headers) — a wrong split is worse than no automation, ask the user to reformat first
- The user wants the spec filed as a Linear **document** (not issue) — use `mcp__claude_ai_Linear__create_document` instead
- The spec is a single rant / brain dump without metadata — file as one ticket and move on

## Procedure

### 1. Parse args

- First positional arg: path to the spec file (required, must exist)
- `--project <name>`: override frontmatter `project`
- `--team <name>`: override frontmatter `team` (default `TOD`)
- `--milestone <name>`: override frontmatter `milestone`
- `--labels <csv>`: override frontmatter `labels` (comma-separated; converted to an array for `save_issue`)
- `--dry-run`: parse + print the planned tickets, do NOT call `save_issue`

### 2. Read the spec file

Use the Read tool. If the file doesn't exist, abort with a clear error. Capture the line count.

**Safety gate:** if `wc -l` > 500 AND `--dry-run` was not passed, refuse and require the user to add `--dry-run` first. Multi-hundred-line specs can accidentally produce 20+ tickets; the dry-run forces a sanity check.

### 3. Parse YAML frontmatter

If the file starts with `---` on line 1, extract everything between that and the next `---`. Parse as YAML (a tiny hand parser is fine — only a handful of scalar keys: `project`, `team`, `milestone`, `labels`).

Defaults if a key is missing AND no CLI override is given:
- `project` — none (omit from save_issue)
- `team` — `TOD`
- `milestone` — none
- `labels` — empty list

CLI flags override frontmatter values.

### 4. Extract the preamble

Everything between the closing `---` of frontmatter (or the start of the file if no frontmatter) and the first section header (`## Part A:` or `## 1.`) is the preamble. Strip leading/trailing blank lines. This becomes a footer in every ticket body so each ticket links back to the umbrella context.

### 5. Parse sections

Walk the body and split on either header style:

- **Lettered**: `## Part A: <title>`, `## Part B: <title>`, ...
- **Numbered**: `## 1. <title>`, `## 2. <title>`, ...

The skill MUST accept both formats in the same file (rare but possible). Letter/number references in `blocked-by` map by position: `A`/`1` → first section, `B`/`2` → second, etc.

For each section, extract:
- **Title**: the text after the marker
- **Priority**: from a `**priority**:` line in the first 10 lines of the section body. Map: `Urgent`→1, `High`→2, `Medium`/`Normal`→3, `Low`→4. Default 3.
- **Blocked-by**: from a `**blocked-by**:` line. Comma-separated list of letter or number references (e.g. `A,B` or `1,2`). `(none)` or missing means no blockers.
- **Body**: everything from after the metadata lines to the next `## Part`/`## N.` header or EOF. Preserve markdown verbatim — no escaping, no re-indenting.

### 6. Validate references

Before any `save_issue` call, walk all `blocked-by` references and verify each letter/number maps to an actual section in the file. Error early with a clear message like `Part C references blocker 'D' but no Part D exists`.

### 7. Build ticket bodies

For each section, the final description is:

```
<section body>

---

## Reference

This ticket is part of a multi-part spec. Full proposal: `<absolute spec path>`

<preamble>
```

Send real newlines, never `\n` escape sequences (per the claude_ai_Linear MCP instructions).

### 8. Dry-run output (if `--dry-run`)

Print a markdown table with columns: index, letter/number, title, priority, blocked-by, body line count. Then print the resolved frontmatter (project / team / milestone / labels). Exit without filing.

### 9. First pass — create tickets

For each section in order, call `mcp__claude_ai_Linear__save_issue` with:
- `title`: section title
- `team`: resolved team
- `description`: built body from step 7
- `project`: resolved project (omit if none)
- `milestone`: resolved milestone (omit if none)
- `priority`: parsed priority
- `labels`: resolved labels array (omit if empty)

**Do NOT** pass `blockedBy` in this pass — the target IDs don't exist yet.

Collect the returned `id` for each section into an ordered list: `[TOD-471, TOD-472, TOD-473, ...]`. The position in this list maps to the letter/number reference from the spec.

Call sequentially, not in parallel — Linear's API is rate-limited and you need the IDs in order anyway.

### 10. Second pass — wire blockedBy

For each section that had a non-empty `blocked-by` list, call `save_issue` again with:
- `id`: the newly-created ticket ID for this section
- `blockedBy`: the array of TOD-IDs from the first pass that the references resolve to

Example: section C had `blocked-by: A,B`, the first pass returned `[TOD-471, TOD-472, TOD-473]` for A/B/C. Second-pass call: `save_issue(id="TOD-473", blockedBy=["TOD-471", "TOD-472"])`.

`blockedBy` is append-only on the Linear MCP — it never removes existing relations. This is the documented behavior, not a bug.

### 11. Third pass (optional) — relatedTo cross-link

For tighter discoverability, call `save_issue` once per ticket with `relatedTo` set to all the OTHER ticket IDs in the batch. This makes them surface together in Linear's related-issues sidebar so the spec stays cohesive.

Skip this pass if the batch is > 6 tickets (the related sidebar gets noisy) or if the user passed `--no-relate` (add this flag if it ever becomes a request).

### 12. Report

Print a markdown table:

| # | ID | Title | Priority | Blocked by | URL |
|---|----|-------|----------|------------|-----|
| 1 | TOD-471 | ... | High | — | https://linear.app/.../TOD-471 |
| 2 | TOD-472 | ... | Medium | TOD-471 | https://linear.app/.../TOD-472 |

Then a one-line summary: `Filed N tickets in <project> / <milestone>, wired M blockedBy relations and K relatedTo links.`

## Safety invariants

- **Never** skip the first-pass / second-pass separation. You cannot reference a Linear ID inside the same `save_issue` call that creates it.
- **Never** escape newlines in description bodies. The Linear MCP wants real newlines — `\n` literals will render as backslash-n in the ticket.
- **Never** file tickets from a > 500-line spec without `--dry-run` first. Specs that long have a high probability of containing more sections than the user intended.
- **Never** invent letter/number references — validate every `blocked-by` against actual parsed sections before any API call.
- **Never** call `save_issue` in parallel — sequential only, both for rate-limit safety and so the ID-collection order is deterministic.
- **Always** include the spec file path in the ticket footer so the umbrella context is one click away.
- **Always** print the URLs in the final report — the user will want to open them immediately.

## Spec file format reference

```markdown
---
project: Reverie
team: TOD
milestone: Phase 5: Auto-Capture & Write-Gate
labels: reverie/coord, reverie/protocol-design
---

# Spec Title

<preamble — context that applies to every part>

## Part A: capability handshake schema
**priority**: High
**blocked-by**: (none)

<body of part A>

## Part B: protobuf wire migration
**priority**: Medium
**blocked-by**: A

<body of part B>

## Part C: custom network protocol
**priority**: Low
**blocked-by**: A,B

<body of part C>
```

Numbered alternative (also supported):

```markdown
## 1. Why
**priority**: Medium
**blocked-by**: (none)

...

## 2. Operation set
**priority**: High
**blocked-by**: 1

...
```

## Example invocation

```
linear-file-spec /tmp/capabilities-protocol-spec-v0.md --milestone "Phase 5: Auto-Capture & Write-Gate" --dry-run
```

Expected dry-run output shape:

```
Spec: /tmp/capabilities-protocol-spec-v0.md (316 lines)
Frontmatter resolved:
  project:   Reverie
  team:      TOD
  milestone: Phase 5: Auto-Capture & Write-Gate
  labels:    [reverie/coord, reverie/protocol-design]

Planned tickets:
| # | Ref | Title                              | Priority | Blocked by | Body lines |
|---|-----|------------------------------------|----------|------------|-----------:|
| 1 | 1   | Why                                | Medium   | —          |         24 |
| 2 | 2   | Operation set                      | High     | 1          |         71 |
| 3 | 3   | Wire format                        | High     | 2          |         48 |
| 4 | 4   | Server runtime                     | Medium   | 3          |         62 |

Dry-run — no tickets filed. Re-run without --dry-run to create.
```

After filing (no `--dry-run`):

```
| # | ID      | Title          | Priority | Blocked by      | URL                                  |
|---|---------|----------------|----------|-----------------|--------------------------------------|
| 1 | TOD-481 | Why            | Medium   | —               | https://linear.app/todie/issue/TOD-481 |
| 2 | TOD-482 | Operation set  | High     | TOD-481         | https://linear.app/todie/issue/TOD-482 |
| 3 | TOD-483 | Wire format    | High     | TOD-482         | https://linear.app/todie/issue/TOD-483 |
| 4 | TOD-484 | Server runtime | Medium   | TOD-483         | https://linear.app/todie/issue/TOD-484 |

Filed 4 tickets in Reverie / Phase 5: Auto-Capture & Write-Gate, wired 3 blockedBy relations and 12 relatedTo links.
```

## Future extensions

- **`--no-relate`** to skip the third pass on big batches
- **`--start <letter>`** to resume a partially-filed batch (e.g. if pass 2 errored mid-flight)
- **`--as-document`** to file the umbrella spec itself as a Linear document and attach all tickets to it
- **Auto-detection of cycles** in the blocked-by graph (currently the validator only checks references exist, not that the DAG is acyclic)
- **Section template inference** — if the user's spec has a `## Acceptance criteria` subsection in each part, auto-promote it to a Linear "Definition of Done" comment
