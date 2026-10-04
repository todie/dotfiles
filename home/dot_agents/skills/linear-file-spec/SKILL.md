---
name: linear-file-spec
description: Parse a multi-section markdown spec file into N linked Linear tickets through `linearctl`. Extracts YAML frontmatter for project/team/milestone/labels, splits the body on `## Part X:` or `## N.` section headers, files one ticket per section (backward `blocked-by` refs wired at creation, forward refs in a second pass), then optionally cross-links relatedTo. Dry-run by default; `--apply` writes. Never the Linear MCP for writes. Use when the user says "file the spec as tickets", "split this into Linear tickets", or pastes a multi-part proposal. Args — required `<spec-path>`; `--team <key>` required unless frontmatter sets `team:`; optional `--project`, `--milestone`, `--labels`, `--no-relate`, `--apply`.
---

# linear-file-spec — markdown spec to linked Linear tickets

Parse a staged markdown spec file (typically in `/tmp/`) into N Linear tickets,
one per top-level "Part" section, then wire the dependency graph between them.

**v2 (2026-10-04).** Rewritten onto `linearctl`. Every write goes through the
CLI, one at a time, each re-read by a different call (`linearctl show <id>
--json`). The Linear MCP is never used for writes (estate SOP
`hold-batch-ops-until-root-cause.md`, OPS-448). The TOD default team is gone:
the team is explicit, every time.

## When to use

- "file this as Linear tickets", "split this spec into tickets", "make tickets
  from this proposal", or a pasted multi-part design doc to be filed
- A spec with 2+ clearly numbered/lettered sections that are each their own
  unit of work, optionally with a dependency order (A blocks B blocks C)

**Don't** use this when:
- The spec is one logical unit — call `linearctl file` directly
- The section structure is ambiguous — a wrong split is worse than no
  automation; ask the user to reformat first
- The spec should be a Linear **document**, not issues — that's `linearctl doc
  create`

## Preconditions

```bash
linearctl --version   # >= 0.7.0
linearctl whoami      # proves LINEAR_API_KEY works; abort on failure, no retry
linearctl ratelimit   # shared org budget; abort below 300 remaining
```

## Procedure

### 1. Parse args

- First positional: spec file path (required, must exist)
- `--team <key>`: team key. Falls back to frontmatter `team:`. **One of the two
  is required — there is no default.** Active teams: CER, OPS, EST, SEC, ONB,
  TOD, RD, BIZ, BRAND, VES.
- `--project <name-or-id>`: override frontmatter `project` (names resolve;
  UUIDs pass through)
- `--milestone <name>`: override frontmatter `milestone` (name lookup needs
  `--project` too)
- `--labels <csv>`: override frontmatter `labels`
- `--no-relate`: skip the relatedTo cross-link pass
- `--apply`: file the tickets. **Default is a dry-run** that prints the plan.

### 2. Read + gate

Read the spec. If `wc -l` > 500 and this is not a dry-run, refuse: long specs
hide extra sections; review the dry-run plan first.

### 3. Parse YAML frontmatter

If line 1 is `---`, extract to the next `---`. Scalar keys only: `project`,
`team`, `milestone`, `labels`. CLI flags override frontmatter.

### 4. Extract the preamble

Everything between frontmatter (or file start) and the first section header.
This becomes a footer in every ticket body linking back to the umbrella
context.

### 5. Parse sections

Split on either header style (both may appear in one file):

- **Lettered**: `## Part A: <title>`
- **Numbered**: `## 1. <title>`

Per section extract:
- **Title** — text after the marker
- **Priority** — `**priority**:` in the first 10 lines. Urgent→1, High→2,
  Medium/Normal→3, Low→4. Default 3.
- **Blocked-by** — `**blocked-by**:` comma list of letter/number refs (`A,B` or
  `1,2`); `(none)` or missing = none. Refs map by section position.
- **Body** — everything else, verbatim markdown, to the next header or EOF.

### 6. Validate references

Every `blocked-by` ref must map to a parsed section. Error early:
`Part C references blocker 'D' but no Part D exists`. Never invent refs.

### 7. Build ticket bodies

```
<section body>

---

## Reference

This ticket is part of a multi-part spec. Full proposal: `<absolute spec path>`

<preamble>
```

### 8. Dry-run output (default)

Print the resolved frontmatter, then a table: index, ref, title, priority,
blocked-by, body line count. End with
`Dry-run — no tickets filed. Re-run with --apply to create.` and exit.

### 9. Apply — pass 1, create tickets

Sequential, never parallel. For each section, in order:

```bash
linearctl file "<title>" \
  --team "<team>" \
  --desc - --priority <n> --json <<'EOF'
<body from step 7>
EOF
```

Add `--project <ref>` / `--milestone <name>` / `--label <name...>` as resolved.
When every `blocked-by` ref of this section points to an **earlier** section,
wire them at creation: `--blocked-by <ID...>` (space-separated identifiers
collected from earlier `--json` output — never comma-joined; commander treats
`"A,B"` as one id and 404s).

Collect `identifier` + `url` per section from the JSON.

### 10. Apply — pass 2, forward refs

For each section whose `blocked-by` references a **later** section (rare, but
valid):

```bash
linearctl update <ID> --blocked-by <target IDs...> --json
```

Append-only: this never removes existing relations (Linear's documented
behavior).

### 11. Apply — pass 3 (optional), relatedTo cross-link

Skip when the batch is > 6 tickets (sidebar noise) or `--no-relate` was passed.
Otherwise, per ticket: `linearctl update <ID> --related-to <all other IDs...>`.

### 12. Re-read and report

Re-read every created ticket with a **different** call than wrote it:

```bash
linearctl show <ID> --json
```

Build the report table from the re-reads (ID, title, state, blocked-by, URL),
then one summary line: `Filed N tickets in <project>/<milestone>, wired M
blockedBy relations and K relatedTo links.`

On HTTP 429 mid-batch: stop, report exactly what landed (identifiers + URLs),
name the resume point (first unfiled section). Never retry-storm; check
`linearctl ratelimit` before resuming.

## Safety invariants

- **Never** write through the Linear MCP. Writes are `linearctl` only,
  sequential, re-read by a different call. Never put ticket IDs in an MCP
  comment body (`hold-batch-ops-until-root-cause.md`).
- **Never** inject markers into descriptions; never write descriptions in bulk
  outside this skill's own create calls.
- **Never** default the team. No `--team` and no frontmatter `team:` → refuse.
- **Never** file a > 500-line spec without a reviewed dry-run first.
- **Never** parallelize `file` calls — sequential only, both for rate limits
  and deterministic ID collection.
- **Never** comma-join IDs in `--blocked-by` / `--related-to` — space-separated.
- **Always** include the spec path in the ticket footer and the URLs in the
  report.
- Dry-run by default; `--apply` writes. Auth failure is a stop, never a retry.

## Spec file format

```markdown
---
project: Reverie
team: CER
milestone: Phase 5
labels: reverie/protocol-design, reverie/observability
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
```

Numbered alternative: `## 1. Why` / `## 2. Operation set` with `blocked-by: 1`.

## Example

```
linear-file-spec /tmp/capabilities-spec-v0.md --team CER --milestone "Phase 5"
```

```
Spec: /tmp/capabilities-spec-v0.md (316 lines)
Resolved: team=CER · project=Reverie · milestone=Phase 5 · labels=[…]

| # | Ref | Title         | Priority | Blocked by | Body lines |
|---|-----|---------------|----------|------------|-----------:|
| 1 | A   | Handshake     | High     | —          |         24 |
| 2 | B   | Wire format   | Medium   | A          |         48 |

Dry-run — no tickets filed. Re-run with --apply to create.
```

## Example script

`scripts/file-spec-example.sh` — runnable end-to-end demo: preflight, dry-run
plan of a tiny two-part spec, and (with `APPLY=1 TEAM=<key>`) the real
file → wire → re-read sequence.

## Future extensions

- `--start <letter>` to resume a partially-filed batch
- Cycle detection across mixed backward/forward refs (backward-only graphs are
  acyclic by construction; mixed graphs are not checked today)
- `--as-document` to file the umbrella spec as a Linear document
  (`linearctl doc create`) and attach the tickets to it
