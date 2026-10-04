---
name: linear-session-ops
description: >
  File, dedupe, groom, announce, and close Linear issues from session activity —
  automatically, as you work, through `linearctl` (never the Linear MCP for
  writes). Use when the operator says "file that", "track this", "park it",
  "dedupe the backlog", "groom", "standup", or when mid-work you surface a
  follow-up, risk, duplicate, or done item that belongs in the shared tracker.
  Args — [<verb>] where verb ∈ file | park | dedupe | groom | followups |
  announce | close | sweep | status. No arg = lifecycle-by-default
  (file-as-you-go + end-of-session announce). No default team or project:
  LINEAR_TEAM / LINEAR_PROJECT must be set or asked for.
---

# Linear session ops — file-as-you-go, groom, announce

The agent doing the work also keeps the shared Linear tracker current — no
operator ticket-filing overhead. Every verb drives `linearctl`.

**v2 (2026-10-04).** The "gami initiative" default binding is removed — scope
is explicit per session (operator env or AskUserQuestion). Flags re-verified
against linearctl 0.7.0; the stale 2026-07 UUID-only gotchas are corrected
(project names resolve everywhere since CER-1604; the dry-run still doesn't
validate them). Writes remain linearctl-only
(`hold-batch-ops-until-root-cause.md`); full flag detail and gotchas live in
`reference.md` beside this file.

## Preconditions

```bash
linearctl --version   # >= 0.7.0
linearctl whoami      # proves LINEAR_API_KEY; abort on failure, no retry
linearctl ratelimit   # shared org budget (2500/hr); abort below 300
```

No `linearctl` on PATH is a setup problem — point the operator at
`mise use -g "github:cerebral-work/linearctl"`. Never fake Linear calls with
raw curl.

## Binding — no defaults

`LINEAR_TEAM` and `LINEAR_PROJECT` come from the operator's env or a per-session
choice. If neither is set, **ask via AskUserQuestion** — never file into the
wrong project. Active teams: CER, OPS, EST, SEC, ONB, TOD, RD, BIZ, BRAND, VES.

```bash
: "${LINEAR_TEAM:?set LINEAR_TEAM (e.g. CER) — no default}"
: "${LINEAR_PROJECT:?set LINEAR_PROJECT (exact name) — no default}"
: "${LINEAR_DEFAULT_STATE:=Backlog}"
```

Optional: `LINEAR_BACKLOG_LABEL` tags parked items so sweeps can find them.

## Attention discipline (non-negotiable)

> **Sourced work parks to Backlog by default; only security · data-loss ·
> prod-breaking · blocks-the-active-ticket interrupts the foreground (one line
> each); findings are reported as a count, never dumped; the backlog is swept
> on a schedule, not reactively.**

- **Park-by-default.** Mid-work findings go to Backlog via `linearctl park` —
  never In Progress, never the operator's Todo.
- **The critical bar** for interrupting: security, data-loss, prod-breaking,
  blocks-the-active-ticket — one line, then file.
- **Report as a count.** "parked 7 to backlog (1 critical: CER-1490)". Never an
  inline dump; the tracker is the system of record, the chat is the index.
- **Promotion is deliberate.** Only the operator promotes Backlog → Todo.
- **No reactive sweeps.** Grooming runs on `announce` or operator trigger.

**File it, don't narrate it; park it, don't promote it; count it, don't dump
it.**

## Verbs

`--json` on everything; mutating verbs are dry-run without `--apply` (or are
single-shot creates shown before filing). Full flag text: `reference.md`.

| verb | call | notes |
|---|---|---|
| file | `linearctl file "<title>" --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --priority 3 --check-dups --desc -` | body on stdin; `--check-dups` always, `--force` only on operator-confirmed false positive |
| park | `linearctl park "<story>" --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --persona "…" --why "…" --accept -` | the default lane for sourced work; lands in Backlog; **no --priority flag** — follow up with `update` if it matters |
| dedupe | `linearctl dupcheck "<title>" --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --threshold 0.85 --limit 5` | read-only; >0.9 + same acceptance ⇒ comment on the dup instead of filing |
| groom | `linearctl triage --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --json` · `linearctl stale --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --older-than 30d --json` | read-only by default; relabel via `stale --label stale --apply` only after the operator sees the table |
| followups | `linearctl comment <ID> --body -` · `linearctl link <ID> <url> --title "…"` · `linearctl update <ID> --blocked-by <ID> <ID>` | relations append-only, **space-separated** (never commas) |
| announce | `linearctl digest --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --since 24h` · `linearctl standup --team "$LINEAR_TEAM" --since 24h` | standup has **no --project flag**; output is markdown you pipe onward — linearctl never auto-posts |
| close | `linearctl comment <ID> --body -` then `linearctl close <ID>` | evidence comment FIRST (what shipped, how verified, what remains), then the flip; re-read with `show <ID> --json` |
| sweep | `linear-groom` skill | full census; announce-time or operator-triggered only |
| status | `linearctl search --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --state started --assignee me --json` · `linearctl show <ID> --json` · `linearctl history <ID> --json` | read-only |

## Workflow

**Session start** — one query, not a sweep:

```bash
linearctl whoami && linearctl ratelimit
linearctl search --team "$LINEAR_TEAM" --project "$LINEAR_PROJECT" --state started --assignee me --json
```

**As you work** — file silently via `park` / `file --check-dups`; collect, then
report the count. At a branch/PR boundary wire the ticket (`link`, `comment`),
and close only when acceptance is fully met, evidence comment first.

**End of session** — `digest` + a one-line operator summary:
`Filed 4 to backlog (1 critical: CER-1490), closed 2, linked PR #567 to
CER-1234. 3 dups caught.` Never a per-ticket dump.

Batch filing uses `cat plan.json | linearctl file --stdin` (dry-run) →
`linearctl file --stdin --apply` — **pipe stdin, never `<` redirect** (sandboxed
shells hand you empty stdin).

## Safety invariants

- Writes through `linearctl` only; never the Linear MCP for writes; never
  ticket IDs in an MCP comment body.
- No default team/project; decisions go through AskUserQuestion.
- Never file into In Progress by default; park-by-default is the lane rule.
- Re-read after every close (`show --json`); comment before close, always.
- Rate-limit hygiene: `ratelimit` before sweeps; on 429 back off (2 s doubling,
  five tries), then stop and report what landed.
- Comments are permanent — one evidence comment per ticket per session, not a
  draft stream.

## Example script

`scripts/session-start-example.sh` — runnable session-start sequence:
precondition trio + "what am I already working on" query, both read-only.

## Reference

`reference.md` — full verb flag detail, batch `--stdin` payloads, the corrected
0.7.0 gotchas, and the operator-portable env configuration.
