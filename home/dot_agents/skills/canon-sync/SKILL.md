---
name: canon-sync
description: Align a project's three sources of truth — spec docs, GitHub PRs, and Linear tickets — by detecting drift between them. Read-only by default; `--apply` performs only the evidence-backed fix (close ticket when its linked PR is merged), through `linearctl`, one write at a time, each re-read. `--ci` exits non-zero on gating drift and runs unattended on `LINEAR_API_KEY`. Reads config from `.canon-sync.yml` at the project root. Use when the user says "canon sync", "align sources of truth", "find drift between specs/PRs/tickets", "what tickets are out of sync with their PRs". Args — optional `--apply`, `--ci`, `--check <csv>` (per-check severity override `<name>=info|warn|gate`), `--specs <glob>`, `--repo <owner/name>`, `--linear-team <key>`, `--linear-project <name>`.
---

# canon-sync — three-way drift detector for project sources of truth

Spec docs in the repo, PRs in GitHub, tickets in Linear: they drift. This
skill walks all three, surfaces the drift, and optionally fixes the *one*
mechanical case — a merged PR linked to an open ticket closes that ticket with
the evidence named. Everything judgment-shaped is reported, never acted on.

**v2 (2026-10-04).** Rewritten onto `linearctl`. All Linear reads go through
`linearctl search --json`; the apply writes are `linearctl comment` +
`linearctl close`, each re-read by `linearctl show --json`. Never the Linear
MCP for writes (`hold-batch-ops-until-root-cause.md`). The TOD default is gone
— team and project are explicit in config or flags. And because linearctl
authenticates with `LINEAR_API_KEY` (not OAuth), `--ci` now runs unattended in
GitHub Actions; see `scripts/canon-sync-ci.example.yml`.

## When to use

- "canon sync", "align sources of truth", "what's out of sync"
- Before a release: confirm every shipped PR closed its ticket
- After planning: confirm every new spec section has a tracking ticket
- Weekly hygiene (pair with `/loop 7d`), or a CI gate on PRs

**Don't** use when:
- There is no `.canon-sync.yml` and no override flags — refuse; vague drift
  detection is worse than none
- You want missing tickets *created* from spec sections — that's
  `linear-file-spec`; auto-filing from drift is too aggressive
- You want PR titles or spec headings rewritten — judgment work

## Config file

`.canon-sync.yml` at the project root:

```yaml
specs: docs/**/*.md
repo: todie/reverie
linear:
  team: CER                  # required — no default. Active teams: CER, OPS, EST, SEC, ONB, TOD, RD, BIZ, BRAND, VES
  project: Reverie           # required — exact name
  closed_states: [Done, Cancelled]   # optional; default is stateType in (completed, canceled)
ticket_re: CER-\d+           # optional; default is "<TEAM>-\d+"
```

CLI overrides: `--specs`, `--repo`, `--linear-team`, `--linear-project`.
Missing any required field → abort: `canon-sync requires .canon-sync.yml (or
--specs --repo --linear-team --linear-project). Refusing to guess.`

**Provider abstraction:** the `linear:` block may grow `jira:`/`gitlab:`
siblings later via a `provider:` discriminator — don't rename `linear:`; that
breaks every config in the wild.

## Procedure

### 1. Parse args + load config

Config + CLI overrides; validate required fields; compile `ticket_re`.

### 2. Preflight — abort on first failure

```bash
git rev-parse --show-toplevel            # in a repo; root == pwd or a parent
gh auth status && gh repo view <repo>    # gh authed, repo reachable
linearctl --version                      # >= 0.7.0
linearctl whoami                         # LINEAR_API_KEY works; no retry on failure
linearctl ratelimit                      # abort below 300 remaining
```

Print: `Preflight: repo=<o/r> (ok) · linear=<TEAM>/<project> (ok) · specs=<glob> (N files) · mode=dry-run`.

### 3. Gather state (three independent batches)

**a) Spec references:** glob `specs`, grep each file for `ticket_re` →
`{ticket_id: [file:line, …]}`; also collect every `## ` heading per file.

**b) PRs:** `gh pr list --repo <repo> --state all --limit 200 --json
number,title,body,state,mergedAt,closedAt,headRefName,commits`. Extract ticket
IDs from title → branch → body → commit subjects, in that trust order; union
per PR. A PR whose only link is a commit subject is tagged `weak-link`.

**c) Linear tickets:** one call:

```bash
linearctl search --team <key> --project <name> --state all --json
```

→ `{identifier: {state, stateType, title, url}}`. "Closed" is `stateType` in
(`completed`, `canceled`) unless `closed_states` overrides by state name.

Cap each source at 500; above that, abort and narrow (`--specs`, smaller
project).

### 4. Drift checks

| check | signal | bucket |
|---|---|---|
| `pr_merged_ticket_open` | PR MERGED, linked ticket not closed | **auto-fixable** (gate) |
| `pr_closed_ticket_open` | PR closed unmerged, ticket open | manual (gate) |
| `ticket_closed_pr_open` | ticket closed, PR open | manual (gate) |
| `spec_ticket_missing` | spec references an ID Linear doesn't have | manual (gate) |
| `pr_no_ticket` | PR with no ticket ref (skip `docs:`/`chore:`/`ci:` titles) | warn |
| `ticket_no_pr` | ticket In Progress/In Review, no PR link | warn |
| `spec_section_no_ticket` | `## ` heading with no `ticket_re` in its section | info |

`--check <csv>` filters; `--check <name>=<severity>` re-buckets (`info|warn|
gate`). Only `gate` rows affect the `--ci` exit code.

### 5. Dry-run output (default)

Three tables — **Auto-fixable**, **Manual review**, **Info** — then:

`N specs scanned, P PRs, T tickets. K auto-fixable, M manual review, I info.
Re-run with --apply to write the K fixes.`

Over ~40 lines of report: write the full report to a file and open `$EDITOR`;
the terminal keeps the summary.

### 6. Apply mode (`--apply`)

Acts on `pr_merged_ticket_open` rows only. Per row, sequential, ≥ 250 ms apart:

```bash
SHORT="$(gh pr view <n> --repo <repo> --json mergeCommit -q .mergeCommit.oid | cut -c1-7)"
linearctl comment <ID> --body "Shipped in #<n> (\`${SHORT}\`)." --json
linearctl close <ID> --json
linearctl show <ID> --json    # assert stateType == "completed"; different call than the write
```

Evidence first: the comment naming the PR + SHA lands **before** the state
flip. On HTTP 429: back off 2 s doubling, five tries, then stop and report
what landed. Any other error: stop, report, surface.

`--ci` and `--apply` are incompatible: `--ci is read-only; remove --apply`.

### 7. CI mode (`--ci`)

- Exit 1 when any `gate`-severity check has rows; 0 otherwise. Warn/info rows
  print but never gate.
- Implies flat ASCII tables and no color.
- Runs unattended: the runner needs `LINEAR_API_KEY` (repo secret) and the
  linearctl binary (`mise use -g "github:cerebral-work/linearctl"` or the
  release tarball). Sample workflow: `scripts/canon-sync-ci.example.yml`.

## Safety invariants

- Writes: `linearctl` only, sequential, re-read by a different call. Never the
  Linear MCP for writes; never ticket IDs in an MCP comment body.
- Auto-fix is limited to `pr_merged_ticket_open`. Never auto-create tickets,
  never auto-reopen, never close on a closed-unmerged PR.
- The closing comment always carries PR number **and** short SHA — the SHA is
  the durable audit, the PR number is the click.
- No default team/project — config or flags, resolved and printed first.
- Auth failure on any of the three sources is a stop, never a retry.

## Example

```
canon-sync                 # from the project root with .canon-sync.yml
canon-sync --apply         # write the auto-fixes
canon-sync --ci            # gate semantics for CI
```

## Example files

- `scripts/canon-sync-ci.example.yml` — GitHub Actions gate job
- `scripts/canon-sync-example.sh` — preflight + dry-run against a configured
  project root (read-only)

## Future extensions

- `--since <date>` window for long-lived projects
- `--export <path>` for the manual-review table
- `Closes CER-NNN` / `Fixes` clause parsing, not just bare regex
- Reverse link: PR mentions ticket → propose PR-URL attachment on the ticket
- Multi-project configs (array of `linear.project`)
