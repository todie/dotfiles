---
name: file-bug
description: Quick single-issue Linear filer for mid-session bug discoveries. Complement to `/linear-file-spec` — that one parses multi-section markdown specs, this one is "I just hit a bug, file it with evidence before I forget." Formats Repro / Evidence / Root cause / Fix direction / Acceptance into the house markdown template, files via `linearctl file` (never the Linear MCP), and re-reads the ticket before reporting. Use when the user says "file a bug", "ticket this", "open an issue for X", "log this in Linear", or when you discover a reproducible defect mid-debug. Args — `<title>` and `--team <key>` required; optional `--project <name-or-id>`, `--priority <1-4>` (default 3), `--related <CER-101,CER-102>` csv, `--labels <bug,observability>` csv, `--apply`.
---

# file-bug — one-shot Linear bug filer with evidence template

Create a single Linear issue with a proper Repro / Evidence / Root cause /
Fix / Acceptance body, without hand-rolling the markdown each time.

**v2 (2026-10-04).** Rewritten onto `linearctl`: the write is
`linearctl file --desc -`, never the Linear MCP
(`hold-batch-ops-until-root-cause.md`). The hardcoded `CER`/`Reverie` target
is gone — the old skill pointed at a dead project binding; `--team` is now
required and `--project` is explicit when used.

## When to use

- "file a bug", "ticket this", "open an issue", "log this in Linear"
- You just hit a reproducible defect mid-debug and want it persisted before
  the context evaporates
- A review/audit finding that doesn't block the current PR but needs the
  backlog

## When NOT to use

- Multi-section specs with Part 1/2/3 and inter-ticket dependencies —
  `/linear-file-spec`
- A vague "we should think about X" with no repro or evidence — discussion,
  not a bug
- A PR review comment — use `gh pr review`
- A user story rather than a defect — `linearctl park`

## Preconditions

```bash
linearctl --version   # >= 0.7.0
linearctl whoami      # abort on auth failure, no retry
linearctl ratelimit   # abort below 300 remaining
```

## Procedure

### 1. Parse args

- `<title>` (positional, required): one line, < 80 chars, imperative. No
  `bug:` prefix — that's what `--labels bug` is for.
- `--team <key>` (required — no default). Active teams: CER, OPS, EST, SEC,
  ONB, TOD, RD, BIZ, BRAND, VES.
- `--project <name-or-id>` (optional): exact project name or UUID.
- `--priority <1-4>` (default 3): 1=Urgent 2=High 3=Medium 4=Low.
- `--labels <csv>` (optional): label names; must exist in the team —
  `linearctl label list --team <key> --json` to check, `label create` to add.
- `--related <csv>` (optional): issue identifiers to link as related.
- `--apply`: write. **Default is a dry-run** that prints the composed body and
  the exact command, and exits.

Refuse an empty title. Redact anything token-shaped from Evidence to
`<REDACTED:token>` before it enters the body.

### 2. Gather the body

If the session already has the five sections, use them verbatim. Otherwise ask
for:

1. **Repro** — bulleted, minimal, copy-pasteable.
2. **Evidence** — code block or log excerpt; truncate past 40 lines with
   `… (N lines elided)`.
3. **Root cause** — 1–3 sentences; "unknown — needs bisect" is acceptable.
4. **Fix direction** — bullets, ordered by preference.
5. **Acceptance** — `- [ ]` checkboxes, each testable.

### 3. Compose

```markdown
## Repro

<bullets>

## Evidence

```
<code or log>
```

## Root cause

<1-3 sentences>

## Fix direction

- <option 1>
- <option 2>

## Acceptance

- [ ] <criterion 1>
```

(Omit empty sections rather than leaving placeholders.)

### 4. File (with `--apply`)

One write, dedupe-checked, body piped on stdin:

```bash
linearctl file "<title>" \
  --team "<team>" --priority <n> --label bug \
  --project "<project>" \
  --check-dups \
  --desc - --json <<'EOF'
<composed body>
EOF
```

`--check-dups` refuses when a likely duplicate exists; re-run with `--force`
only when the operator confirms a false positive (say why in the body).

If `--related` was given, wire it after creation (append-only, space-separated):

```bash
linearctl update <ID> --related-to <ID1> <ID2> --json
```

### 5. Re-read and report

Verify with a different call than wrote it:

```bash
linearctl show <ID> --json
```

Assert the state is the team's default and the title matches. Report one line:

```
filed CER-731: <title> — https://linear.app/cerebral-work/issue/CER-731
```

## Safety invariants

- Writes through `linearctl` only — never the Linear MCP; never a ticket ID in
  an MCP comment body.
- No default team or project — both explicit, every time.
- Never file without a title; never file secrets (redact Evidence first).
- Dry-run by default; `--apply` writes; the ticket is re-read before the
  report.
- One ticket per invocation — batch filing is `linear-file-spec` or
  `linearctl file --stdin`.

## Examples

```
file-bug "cortex dash loses heartbeat on terminal resize" --team CER --project Reverie --priority 2 --labels bug,observability
file-bug "status JSON drops role on stale records" --team CER --labels bug --related CER-725 --apply
```

## Example script

`scripts/file-bug-example.sh` — preflight + dry-run body render; with
`APPLY=1 TEAM=<key>` files a demo bug and re-reads it.

## Related skills

- `/linear-file-spec` — multi-section specs with dependencies
- `/close-ticket` — flip an existing ticket to Done with shipping evidence
- `/push-close` — push main and close every ticket named in commit messages
