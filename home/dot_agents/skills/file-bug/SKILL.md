---
name: file-bug
description: Quick single-issue Linear filer for mid-session bug discoveries. Complement to `/linear-file-spec` — that one parses multi-section markdown specs, this one is "I just hit a bug, file it with evidence before I forget." Formats Repro / Evidence / Root cause / Fix direction / Acceptance into the house markdown template, creates a Linear issue in team=CER (Cerebral Work Institute) project=Reverie via the claude_ai_Linear MCP, and reports the new CER-ID. Use when the user says "file a bug", "ticket this", "open an issue for X", "log this in Linear", or when you discover a reproducible defect mid-debug. Args — `<title>` required, `--priority <1-4>` (default 3), `--related <CER-101,CER-102>` csv of related tickets, `--labels <bug,observability>` csv of label names.
---

# file-bug — one-shot Linear bug filer with evidence template

Create a single Linear issue with a proper Repro / Evidence / Root cause / Fix / Acceptance body, without hand-rolling the markdown each time. Built for the "I hit a bug while debugging something else — file it before the context evaporates" case. Uses the house evidence template so the team reads the same shape every time.

> **Team migration (2026-05-21):** reverie tickets moved from legacy team Todie (TOD) to **Cerebral Work Institute (CER)**. This skill files to **CER**; legacy `TOD-NNN` in old examples below are historical.

## When to use

- User says "file a bug", "ticket this", "open an issue", "log this in Linear", "create a CER" (or "a TOD" out of habit)
- You (Claude) just hit a reproducible defect mid-debug and want to persist it before switching contexts
- You found a bug in a review / audit that doesn't block the current PR but needs to land on the backlog

## When NOT to use

- Multi-section specs with Part 1 / Part 2 / Part 3 and inter-ticket dependencies — use `/linear-file-spec` instead.
- A vague "we should think about X" without repro steps or evidence — that's a discussion topic, not a bug.
- A PR review comment — use `gh pr review` or a sticky comment.
- A feedback note about the conversation — that's auto-memory, not Linear.

## Procedure

### 1. Parse args / preconditions

- `<title>` (positional, required): the one-line ticket title. Keep under 80 chars. Do not prefix with `bug:` — use `--labels bug` instead.
- `--priority <1-4>` (default 3): Linear priority. 1=Urgent, 2=High, 3=Medium, 4=Low.
- `--related <ids>` (csv): e.g. `--related TOD-724,TOD-725`. Each is appended as a `Related: <id>` bullet in the body.
- `--labels <labels>` (csv): label names. Must exist in the Reverie project or they're ignored by Linear.

Preflight:
- Confirm the claude_ai_Linear MCP is available (tools prefixed `mcp__claude_ai_Linear__*`).
- Refuse to file if `<title>` is empty.

### 2. Gather the body

If the calling session already has the five sections in context, use them verbatim. If not, ask the caller for:

1. **Repro steps** — bulleted, minimal, copy-pasteable commands or actions.
2. **Evidence** — code block or log excerpt. Inline with triple backticks. If >40 lines, truncate with `… (N lines elided, full log attached as artifact on request)`.
3. **Root cause hypothesis** — 1–3 sentences. OK to say "unknown — needs bisect" if genuinely unknown.
4. **Fix direction** — bullets, ordered by preferred approach. It's fine to enumerate 2–3 alternatives.
5. **Acceptance criteria** — bullets starting with checkbox syntax `- [ ]`. Each criterion must be testable.

### 3. Format the body

Use this exact template (matches TOD-723/724/725/730):

```markdown
## Repro

<bullets>

## Evidence

```
<code or log block>
```

## Root cause

<1-3 sentences>

## Fix direction

- <option 1>
- <option 2>

## Acceptance

- [ ] <criterion 1>
- [ ] <criterion 2>

## Related

- <CER-XXX>
- <CER-YYY>
```

Omit the `## Related` block entirely if `--related` is empty.

### 4. File via Linear MCP

Call `mcp__claude_ai_Linear__save_issue` with:

- `team`: `CER` (Cerebral Work Institute)
- `project`: `Reverie`
- `title`: `<title>` positional arg
- `description`: the composed markdown body (send real newlines, not `\n` escapes — per the claude_ai_Linear MCP instruction)
- `priority`: numeric from `--priority`
- `labels`: array from `--labels` csv

Capture the returned issue identifier (e.g. `CER-731`) and URL.

### 5. Report

One line only:

```
filed CER-731: <title> — https://linear.app/cerebral-work/issue/CER-731
```

No rehashing the body content — the user can click through.

## Examples

```
/file-bug "cortex dash loses heartbeat when terminal is resized" --priority 2 --labels bug,observability --related TOD-725
```

Files a P2 bug with labels `bug,observability`, a Related bullet linking TOD-725, and the standard evidence template populated from session context.

```
/file-bug "cortex status JSON output drops role on stale records" --labels bug,observability

Files a P3 bug (default) with `bug,observability` labels and no related tickets.

## Safety invariants

- Never file without a title.
- Never embed secrets in the Evidence block. If a log line contains what looks like a token/key, redact to `<REDACTED:token>` before filing.
- Never file under a different team/project than `CER`/`Reverie` from this skill — if you need a different target, call the Linear MCP directly.
- Always use real newlines in the description (the claude_ai_Linear MCP rejects escape sequences).

## Related skills

- `/linear-file-spec` — multi-section specs with inter-ticket dependencies (use that instead for Part 1 / Part 2 structure).
- `/close-ticket` — flip an existing TOD to Done with a shipping-commit comment.
- `/push-close` — push main and auto-close every TOD mentioned in commit messages since last push.
