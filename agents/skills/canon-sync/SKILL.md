---
name: canon-sync
description: Align a project's three sources of truth — spec docs, GitHub PRs, and Linear tickets — by detecting drift between them. Read-only by default; `--apply` performs only the cheap/safe fixes (close ticket when its linked PR is merged, post PR-link comment on ticket). `--ci` exits non-zero on drift so the skill can run as a GitHub Action gate. Reads source config from `.canon-sync.yml` at the project root. Use when the user says "canon sync", "align sources of truth", "find drift between specs/PRs/tickets", "what tickets are out of sync with their PRs". Args — optional `--apply`, `--ci`, `--check <csv>` (default: all; supports per-check severity override `<name>=info|warn|gate`, e.g. `--check spec_section_no_ticket=warn`), `--specs <glob>`, `--repo <owner/name>`, `--linear-project <name>` to override config.
---

# canon-sync — three-way drift detector for project sources of truth

A project has three places where work-state lives: spec docs in the repo, PRs in GitHub, and tickets in Linear. They drift. This skill walks all three, surfaces the drift, and optionally fixes the *mechanical* drift (a merged PR linked to an open ticket → close the ticket). Anything that requires judgment (a spec section with no ticket, a PR title that doesn't match its ticket) gets reported, not auto-fixed.

## When to use

- User says "canon sync", "align sources of truth", "what's out of sync", "find drift between specs and Linear"
- Before a release — sweep to confirm every shipped PR closed its ticket
- After a planning session — sweep to confirm every new spec section has a tracking ticket
- Recurring weekly hygiene loop (pair with `/loop 7d /canon-sync`)

**Don't** use this when:
- The project has no `.canon-sync.yml` and no override flags — refuse and tell the user to create the config (see "Config file" below). Vague drift detection is worse than no drift detection.
- The user wants to *create* missing tickets from spec sections — that's `linear-file-spec`, not this skill. Auto-filing tickets from drift is too aggressive a default.
- The user wants to rewrite PR titles or spec headings — judgment work, not mechanical.

## Config file

The skill reads `.canon-sync.yml` at the project root (the directory you invoke from). Schema:

```yaml
specs: docs/**/*.md          # glob of spec files (relative to project root)
repo: todie/reverie          # github owner/name
linear:
  team: TOD                  # team key
  project: Reverie           # exact project name
  # Optional:
  closed_states: [Done, Cancelled]   # which Linear states count as "closed"
ticket_re: TOD-\d+           # regex for ticket IDs in this project (default: TOD-\d+)
```

**Provider abstraction (future-compatible):** the `linear:` block is one of several possible ticket-tracker providers. The shape is fixed today (Linear only) but the key name leaves the door open for `jira:` or `gitlab:` siblings. If you find yourself wanting Jira support, add a `provider: jira` discriminator to the existing `linear:` block — don't rename it; rename breaks every `.canon-sync.yml` in the wild. Same goes for `repo:` (GitHub today; could grow a `provider: gitlab` discriminator later).

CLI flags override the config:
- `--specs <glob>` overrides `specs`
- `--repo <owner/name>` overrides `repo`
- `--linear-project <name>` overrides `linear.project`

If both config and overrides are missing for any required field → abort with: `canon-sync requires .canon-sync.yml at the project root (or --specs --repo --linear-project flags). Refusing to guess.`

### 1. Parse args + load config

Read `.canon-sync.yml` if present. Apply CLI overrides. Validate: `specs`, `repo`, `linear.team`, `linear.project` must all be set. Compile `ticket_re`.

### 2. Preflight

Three cheap calls, in this order. Abort on the first failure.

- **Git**: `git rev-parse --show-toplevel` to confirm you're in a repo. The project root must equal `pwd` (or a parent — adjust glob resolution accordingly).
- **GitHub**: `gh auth status` to confirm gh CLI is authed and `gh repo view <repo>` to confirm access. On failure → `gh CLI not authed or repo unreachable. Run: gh auth login` and stop.
- **Linear OAuth**: `mcp__claude_ai_Linear__list_teams`. If auth-shaped error → `Linear OAuth expired. Re-auth with: /mcp` and stop.

Print one preflight line:
```
Preflight: repo=todie/reverie (ok) · linear=TOD/Reverie (ok) · specs=docs/**/*.md (N files) · mode=dry-run
```

### 3. Gather state

Build three lists in parallel (each is a separate batch — independent, no interleaving needed):

**a) Spec references**: glob the `specs` pattern, grep each file for `ticket_re`. Build a map `{ticket_id: [file:line, ...]}`. Also collect every `## ` heading in each spec file (for "untracked work" detection).

**b) Open PRs**: `gh pr list --repo <repo> --state all --limit 200 --json number,title,body,state,mergedAt,closedAt,headRefName,commits`. For each PR, extract ticket IDs from four signals, in order of trust:

1. `title` — high signal
2. `headRefName` — high signal (branch convention like `tod-512-fix-foo`)
3. `body` — medium signal
4. Commit subjects in `commits` (the `messageHeadline` of each) — medium signal; catches PRs that didn't put the ticket in title/branch/body but did in `git commit -m "TOD-512: ..."`

Union the matches per PR. If a PR has a ticket ID in commits but not in title/branch/body, tag it in the report as `weak-link` so the user knows the convention slipped. Build `{pr_number: {state, ticket_ids, link_strength, ...}}`.

**c) Linear tickets**: `mcp__claude_ai_Linear__list_issues` filtered to `team=<team>` AND `project=<project>`. State filter: all states (including Done/Cancelled — we need to know what's closed). Build `{ticket_id: {state, title, ...}}`.

Cap each list at 500. If any exceeds, abort with `<source> returned >500 items — narrow with --specs or use a smaller project`.

### 4. Run drift checks

Each check is independent; tag every drift instance with `{kind, evidence, auto_fixable: bool, proposed_action}`.

- **pr_merged_ticket_open**: PR state = `MERGED` AND linked ticket state ∉ `closed_states`. → **auto-fixable**: close the ticket with a comment `"Shipped in #<pr> (<sha>)"`. *This is the main thing this skill exists to fix.*

- **pr_closed_ticket_open**: PR state = `CLOSED` (not merged) AND ticket state ∉ `closed_states`. → report only — closed-without-merge usually means the work was abandoned or moved; needs human judgment.

- **ticket_closed_pr_open**: Ticket state ∈ `closed_states` AND linked PR state = `OPEN`. → report only — usually means the ticket was prematurely closed.

- **pr_no_ticket**: PR has no ticket reference in title/body/branch AND PR is not a docs/chore PR (best-effort: skip PRs whose title starts with `docs:`, `chore:`, `ci:`). → report only.

- **ticket_no_pr**: Ticket is `In Progress` or `In Review` AND has no PR reference in spec or PR list. → report only — flag for tracking-link hygiene.

- **spec_ticket_missing**: Spec file references a ticket ID that doesn't exist in Linear (typo'd or wrong project). → report only.

- **spec_section_no_ticket**: A `## ` heading in a spec file with no `ticket_re` match within the section (next heading or EOF). Default severity *info* — most spec sections legitimately don't need tickets. Severity is configurable per-check (see below).

Use `--check <csv>` to filter the set. Names: `pr_merged_ticket_open,pr_closed_ticket_open,ticket_closed_pr_open,pr_no_ticket,ticket_no_pr,spec_ticket_missing,spec_section_no_ticket`.

**Per-check severity override** (`--check <name>=<severity>`): bumps a check between buckets. Severities: `info` (shown in Info table, never gates CI), `warn` (shown in Manual review table, never gates CI), `gate` (shown in Manual review table, gates `--ci` exit code). Example: `--check spec_section_no_ticket=warn` promotes untracked spec sections to manual-review on a planning-heavy project that wants every section ticketed. Default severities: `pr_merged_ticket_open`/`pr_closed_ticket_open`/`ticket_closed_pr_open`/`spec_ticket_missing` are `gate`; `pr_no_ticket`/`ticket_no_pr` are `warn`; `spec_section_no_ticket` is `info`. Override syntax composes with filter syntax: `--check spec_section_no_ticket=warn,pr_no_ticket=gate` filters to those two checks AND sets their severities.

### 5. Dry-run output (default)

Three sections:

**Auto-fixable** (close ticket when PR merged + linked):
| Ticket | State | PR | Merged | Proposed action |
|--------|-------|----|----|--------------|
| TOD-512 | In Review | #87 | 2026-05-20 | close ticket + comment "Shipped in #87 (abc1234)" |

**Manual review needed**:
| Kind | Evidence | Notes |
|------|----------|-------|
| pr_closed_ticket_open | PR #92 closed without merge, TOD-518 still In Progress | likely abandoned |
| spec_ticket_missing | docs/protocol.md:42 references TOD-999 | not found in Linear |
| ticket_no_pr | TOD-523 In Progress, no PR link | tracking gap |

**Info** (spec sections without tickets — usually fine):
| Spec | Heading |
|------|---------|
| docs/release-notes.md | ## 0.4.0 changes |

Then summary: `N specs scanned, P PRs, T tickets. K auto-fixable, M manual review, I info. Re-run with --apply to write the K auto-fixes.`

### 6. Apply mode (`--apply`)

Only acts on `pr_merged_ticket_open` rows. For each:

- Call `mcp__claude_ai_Linear__save_comment` with `issueId=<ticket>, body="Shipped in #<pr> (<short-sha>)"`. The SHA comes from `gh pr view <pr> --json mergeCommit -q .mergeCommit.oid` (short-form via `cut -c1-7`).
- Then `mcp__claude_ai_Linear__save_issue` with `id=<ticket>, state=Done`.
- Sequential. 100ms delay between tickets (10/sec target). Exponential backoff (2s, 4s, 8s, 16s, 32s, max 5 retries) on rate-limit.
- On any non-rate-limit error: abort apply loop, report what landed.

After the loop:
```
Applied: 5 tickets closed, 0 failures, 0 rate-limit retries
Manual review still needed: 8 items
```

### 6b. CI mode (`--ci`)

When the skill runs as a GitHub Action (or any CI step), `--ci` changes the exit semantics:

- Exit `0` only when there are zero drift signals across checks whose severity is `gate`. Default gating set: `pr_merged_ticket_open`, `pr_closed_ticket_open`, `ticket_closed_pr_open`, `spec_ticket_missing`. The set is recomputed if the user overrode severity via `--check <name>=gate` (e.g. `--check spec_section_no_ticket=gate` adds untracked spec sections to the gate).
- Exit `1` when any gating-severity check has at least one row. Print the gating tables only (skip info/warn rows).
- Checks at severity `warn` (default: `pr_no_ticket`, `ticket_no_pr`) are printed but never gate exit. Most teams have legitimate ticketless PRs (docs/chore) and ticketless in-flight tickets.
- `--ci` implies `--no-color` and a flat ASCII table (no Unicode box-drawing). CI log readers and PR-comment markdown both render plain ASCII more reliably.
- `--ci` is **incompatible with** `--apply`: a CI run that auto-mutates Linear from a PR is too easy to misuse (a contributor's PR could close someone else's ticket). Refuse with `--ci is read-only; remove --apply`.

Recommended GitHub Action invocation lives in step 9 below.

### 7. Exit

Return cleanly. Do not auto-loop. Exit code: `1` in `--ci` mode with gating drift, `0` otherwise.

## Safety invariants

- **Never** auto-create tickets from drift. Filing missing tickets is judgment work — surface, don't act.
- **Never** auto-close a ticket without a clear linked-and-merged PR. The `pr_closed_ticket_open` case (closed without merge) stays manual because "PR closed" alone doesn't mean the work shipped.
- **Never** auto-reopen tickets. Reopening crosses too many workflows (someone might have closed it deliberately).
- **Never** rewrite PR titles, ticket titles, or spec content. All textual alignment is judgment work.
- **Always** print the resolved sources before doing anything. The wrong-workspace bug from your insights report applies to the wrong-project bug here too.
- **Always** preflight all three sources. Discovering gh auth is dead halfway through a 200-PR scan is the friction this skill is designed to prevent.
- **Always** include the PR number AND short SHA in the closing comment. The SHA is what makes the audit trail durable; the PR number is what makes it clickable.
- **Never** continue after an auth failure on any of the three sources — stop and surface the reauth path.

## Example config

`.canon-sync.yml` in `~/projects/reverie/`:

```yaml
specs: docs/**/*.md
repo: todie/reverie
linear:
  team: TOD
  project: Reverie
  closed_states: [Done, Cancelled, Released]
ticket_re: TOD-\d+
```

## Example invocation

From the project root:

```
canon-sync
```

Expected dry-run output:

```
Preflight: repo=todie/reverie (ok) · linear=TOD/Reverie (ok) · specs=docs/**/*.md (42 files) · mode=dry-run

Auto-fixable:
| Ticket  | State     | PR  | Merged     | Proposed action                          |
|---------|-----------|-----|------------|------------------------------------------|
| TOD-512 | In Review | #87 | 2026-05-20 | close + comment "Shipped in #87 (abc1234)" |
| TOD-518 | In Review | #91 | 2026-05-22 | close + comment "Shipped in #91 (def5678)" |

Manual review needed:
| Kind                  | Evidence                                          | Notes              |
|-----------------------|---------------------------------------------------|--------------------|
| pr_closed_ticket_open | PR #92 closed (not merged), TOD-520 In Progress   | likely abandoned   |
| spec_ticket_missing   | docs/protocol.md:42 references TOD-999            | not found in Linear |
| ticket_no_pr          | TOD-523 In Progress, no PR link                   | tracking gap       |

Info (spec sections without tickets — usually fine):
| Spec                    | Heading           |
|-------------------------|-------------------|
| docs/release-notes.md   | ## 0.4.0 changes  |

42 specs scanned, 38 PRs, 71 tickets. 2 auto-fixable, 3 manual review, 1 info. Re-run with --apply to write the 2 auto-fixes.
```

After `--apply`:

```
Applied: 2 tickets closed, 0 failures, 0 rate-limit retries
Manual review still needed: 3 items
```

## Running `--ci`

`--ci` makes the skill return exit code 1 on gating drift, suitable for use as a CI gate. **However**, the Linear MCP this skill relies on (`mcp__claude_ai_Linear__*`) is OAuth-based via claude.ai and is not runnable unattended in GitHub Actions today. To wire `--ci` into CI you need a Linear MCP transport that authenticates via API key — e.g. a self-hosted MCP shim using `LINEAR_API_KEY`. Once that's in place, the invocation is `claude --print /canon-sync --ci` from a checkout-and-skills-mounted runner.

Until that transport exists, the realistic use of `--ci` is:
- Running it locally before pushing (`canon-sync --ci && git push`)
- Running it from a self-hosted runner that already has the claude.ai MCP session
- Running it from `reveried`'s scheduled-agent surface if it grows a `--ci` toggle

The exit-code semantics are the contract; the deployment path is yours to wire up.

## Future extensions

- `--since <date>`: only consider PRs/tickets touched after a date (faster on long-lived projects)
- `--export <path>`: dump the manual-review table to markdown for offline triage
- Smarter PR/ticket linking: parse `Closes TOD-NNN` / `Fixes #N` clauses, not just regex matches anywhere
- Reverse direction: when a PR mentions a ticket but the ticket has no PR link, propose adding the PR URL to the ticket as an attachment
- ~~`--strict-untracked`: promote `spec_section_no_ticket` from info to manual-review~~ — superseded by per-check severity override (`--check spec_section_no_ticket=warn`); see Args section
- Multi-project config: array of `linear.project` entries to align several Linear projects against one repo
- Jira / GitLab adapters (config shape already leaves room — see "Provider abstraction" in the Config section)
- Semantic spec-to-ticket matching: AI pass that detects "this spec section is *about* TOD-512 even without a literal ID" (deep, horizon feature)
- Sample GitHub Actions workflow snippet shipped alongside the skill (`.github/workflows/canon-sync.yml.example`) so users can drop in `--ci` mode without writing the YAML
