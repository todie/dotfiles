# linear-session-ops reference — verb detail + gotchas (linearctl 0.7.0)

Flag text verified against `linearctl <cmd> --help` at 0.7.0 on 2026-10-04.
When linearctl moves ahead of this file, the `--help` output wins — check it.

## file

```
linearctl file "<title>" --team <key> [--project <name-or-id>] [--priority 0-4]
  [--label <name...>] [--assignee <who>] [--milestone <ref>] [--cycle <ref>]
  [--parent <id>] [--blocked-by <id...>] [--related-to <id...>]
  [--check-dups [--force]] --desc - --json
```

- Headless requires `--team` — the CLI errors `file needs --team <key>` without
  it (name inference is TTY-only).
- `--desc -` reads markdown from stdin; pipe or heredoc, never `<` redirect in
  sandboxed shells.
- Body shape: Context → What → Acceptance → Source (one-line session
  provenance). Priority defaults to 3; 1 only for the critical bar, never
  auto-Urgent.

### Batch: `file --stdin [--apply]`

```bash
cat plan.json | linearctl file --stdin          # dry-run preview (default)
cat plan.json | linearctl file --stdin --apply  # creates, sequential, per-item errors
```

Item shape: `{title, team?, desc?, labels?, project?, assignee?, priority?,
milestone?, parent?}` (JSON array or NDJSON). Since 0.7.0 (CER-1604) the
`project` field accepts names **and** UUIDs — the 2026-07 "UUID required"
note is stale. The dry-run preview still does NOT resolve/validate project
refs, so a name that `--apply` will reject still prints "would create".

## park

```
linearctl park "<title>" --team <key> [--project <name-or-id>] [--persona <name>]
  [--want <text>] [--why <text>] [--accept -] [--label <name...>] --json
```

- Lands in Backlog with the `sourced` label; composes a persona/want/why
  story body.
- **No `--priority` flag** — stories land unprioritized; follow up with
  `linearctl update <ID> --priority <n>` when it matters.
- Project names resolve (same CER-1604 path as `file`).

## dedupe (`dupcheck`)

```
linearctl dupcheck "<title>" [--team <key...>] [--project <ref>]
  [--threshold 0.85] [--limit 5] --json
```

Threshold guide: 0.85 default catches most; below 0.8 is noise; above 0.9
misses reformulations. `file --check-dups` runs this inline and refuses.

## groom (`triage` / `stale`)

```
linearctl triage [--team <key...>|all] [--project <ref>] --json
linearctl stale  [--team <key...>|all] [--project <ref>] [--older-than 30d]
                 [--label <name> [--apply]] --json
```

`triage` surfaces Triage-state plus unassigned/unestimated/no-priority issues.
`stale` is report-only unless `--label … --apply`. Reassignment/estimation/
priority are post-table operator decisions, never automatic.

## followups

```
linearctl comment <ID> --body -            # markdown on stdin; additive only
linearctl link <ID> <url> [--title <text>]
linearctl update <ID> --blocked-by <ID> <ID>   # space-separated; append-only
linearctl update <ID> --related-to <ID> <ID>   # same
linearctl update <ID> --state <name> --priority <0-4> --assignee <who> …
```

Comments are permanent: one batched evidence comment per ticket per session.
`update --label` **replaces** the label set — to add, pass old + new together.
Bulk plans: `cat plan.json | linearctl update --stdin --apply`
(`{id,labels?,addLabels?,priority?,project?,assignee?,milestone?}`; note: no
`state` key in the stdin plan — single-issue `update --state` for transitions).

## announce

```
linearctl digest  [--team <key...>] [--project <ref>] [--since 7d] --json
linearctl standup [--team <key...>] [--since 24h] [--json]
                  [--slack <webhook-url> [--apply]]
```

`standup` has **no `--project` flag** (0.7.0) — scope it by `--team`.
linearctl never auto-posts; `--slack` is dry-run unless `--apply`, and posting
is still your message to send.

## close

```
linearctl close <ID> --json
linearctl show <ID> --json      # re-read: stateType should be "completed"
linearctl history <ID> --json   # when the close didn't land
```

Evidence comment first (`comment --body -`), then close, then re-read. Closes
need evidence: merged PR sha, all children done, or a live check named in the
comment.

## status / search / show / history

```
linearctl search [--team <key...>|all] [--project <ref>] [--state <ref>]
  [--label <name...>] [--assignee <who>] [--text <q>]
  [--updated-since 7d] [--created-since 7d] --json
linearctl show <ID> --json
linearctl history <ID> [--limit 20] --json
```

`--state` takes a state **type** (`triage|backlog|todo|started|done|canceled|
all`) or an exact state name; default is active-only.
`show --json` fields: id, identifier, title, state, stateType, priority,
labels, description, project, assignee, parent, url, createdAt, updatedAt
(no milestone field in 0.7.0).

## Gotchas

- **Rate limit is a shared org budget.** `linearctl ratelimit` before
  request-heavy sweeps. Complexity budget (3M/hr) is the tighter constraint on
  large queries. On 429: back off 2 s doubling, five tries, then stop — never
  spin.
- **Space-separated relation IDs.** `--blocked-by CER-1200 CER-1199`, never
  `"CER-1200,CER-1199"` (one token → 404).
- **Dry-run previews don't resolve refs.** The `--stdin` dry-run prints the
  plan without validating project/milestone names; `--apply` is where bad refs
  error.
- **`update --label` replaces.** Adding a label means passing the full new set.
- **stdin via pipe, never `<`.** Sandboxed shells deliver empty stdin on
  redirect; `cat plan.json | linearctl update --stdin --apply` is the safe
  shape.
- **Never In Progress by default.** `file` creates in the team's default
  state; `park` creates in Backlog explicitly. Only the operator promotes.

## Operator configuration (any operator, any project)

No defaults ship with the skill. Set the binding per operator, e.g. in the
harness env block:

```jsonc
// ~/.claude/settings.json (or the harness equivalent)
{ "env": { "LINEAR_TEAM": "CER", "LINEAR_PROJECT": "Reverie",
           "LINEAR_DEFAULT_STATE": "Backlog" } }
```

`linearctl mcp serve` exposes the same operations as a stdio MCP server for
harnesses that can't shell out — the CLI remains the canonical surface
(`dupcheck`, `park`, batch stdin, dry-run previews).
