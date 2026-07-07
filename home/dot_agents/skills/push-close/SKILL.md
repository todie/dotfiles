---
name: push-close
description: After commits land locally on main, push them to origin and auto-close every `TOD-NNN` mentioned in commit subjects since the last push — each via `/close-ticket` with the short SHA of the commit that introduced it. Use when the user says "push and close", "ship it and close the tickets", "push main", or after a batch of fix commits that should drop a set of Linear issues. Args — none required, optional `--dry-run` to list what would be pushed and closed without acting.
---

# push-close — push main + close every TOD-ID in the new commits

Combine `git push origin main` with a sweep of every `TOD-NNN` reference in the commit subjects between `origin/main` and `HEAD`, closing each via `/close-ticket` with the short SHA of the commit that introduced it. Built for the release cadence where a batch of small fixes lands on main and the Linear board needs to reflect reality in one action.

## When to use

- User says "push and close the tickets", "push main", "ship and update Linear", "close everything this push drops"
- After a batch of commits with `TOD-` references in subjects that haven't been pushed yet
- Inside `/cut-release` or release workflows as the "update Linear" step (though cut-release proper is tag + push, not ticket close)

## When NOT to use

- Commits haven't landed locally yet — commit first.
- You want to push a branch, not main — use `gh pr create` / `git push origin <branch>`.
- TOD-IDs in commit messages refer to tickets that are NOT fully shipped by this push (e.g. Part 1 of 3) — close them manually with a partial-progress comment instead.
- You want to force-push — this skill refuses force-push against main.

## Procedure

### 1. Parse args / preconditions

- `--dry-run`: print the plan (commits to push, tickets to close, per-ticket SHA) but take no action. Default: off.

Preflight:
```bash
cd ~/projects/reverie
git rev-parse --abbrev-ref HEAD | grep -qx main \
  || { echo "ERROR: not on main branch — push-close only operates on main"; exit 1; }

if [ -z "$(git log --oneline origin/main..HEAD 2>/dev/null)" ]; then
  echo "nothing to push — HEAD is at origin/main"
  exit 0
fi
```

### 2. Extract TOD-IDs + their introducing SHAs

```bash
git -C ~/projects/reverie log --format='%h %s' origin/main..HEAD \
  | python3 -c '
import sys, re
seen = {}  # TOD-ID -> first SHA that mentions it (oldest-first scan)
# git log is newest-first; reverse so earliest mention wins
lines = list(sys.stdin)
for line in reversed(lines):
    line = line.rstrip()
    if not line:
        continue
    sha, _, subj = line.partition(" ")
    for tod in re.findall(r"\bTOD-\d+\b", subj):
        seen.setdefault(tod, sha)
for tod, sha in seen.items():
    print(f"{tod} {sha}")
'
```

Result: one line per unique TOD-ID with the short SHA of the commit that first mentioned it (going oldest → newest so the "introducing" SHA is stable).

### 3. Push (or report in dry-run)

```bash
if [ -n "$DRY_RUN" ]; then
  echo "DRY RUN — would run: git push origin main"
  echo "DRY RUN — would close:"
  cat /tmp/push-close-tickets.$$
  exit 0
fi

git push origin main || { echo "ERROR: git push failed — aborting ticket closes"; exit 1; }
```

Refuse force-push: never pass `-f` or `--force-with-lease`. If the push fails because origin has diverged, stop and report — don't attempt to rewrite history.

### 4. Close each ticket

For each `<TOD-ID> <short-sha>` pair from step 2, invoke the `/close-ticket` skill (or the equivalent MCP calls directly — save_comment then save_issue state=Done). Pass:

- `<TOD-ID>` and `<short-sha>` positionally.
- No `--note` (this is the bulk close; add notes manually if needed).

If a close fails for one ticket, log the failure and continue to the next — partial success beats all-or-nothing here.

### 5. Report

```
push-close:
  pushed 4 commits to origin/main (abc1234..f8b2001)
  closed 3 tickets:
    TOD-724 → Done (shipped in a4f2c19)
    TOD-725 → Done (shipped in e8d0342)
    TOD-730 → Done (shipped in f8b2001)
  1 failure:
    TOD-723 — save_issue returned 404 (ticket may be archived)
```

If dry-run, prefix with `DRY RUN — no changes made` and list the same plan without executing.

## Examples

```
/push-close
```

Pushes `origin/main..HEAD`, extracts each unique TOD-ID from commit subjects, closes each with its introducing commit's short SHA.

```
/push-close --dry-run
```

Lists what would be pushed and which tickets would be closed with which SHAs. No network or Linear mutations.

## Safety invariants

- Never force-push. `git push origin main` only — if it fails because of divergence, stop.
- Must be on the `main` branch (checked in preflight). Never push from a feature branch via this skill.
- Never close a ticket whose introducing SHA can't be resolved — `/close-ticket` already preflights `rev-parse --verify`, let it refuse.
- Partial failures on ticket closes do NOT roll back the push — once main is pushed, it's pushed. Report failures clearly.
- Never skip `--dry-run` if asked.

## Related skills

- `/close-ticket` — single-ticket close (this skill calls it per TOD-ID).
- `/cut-release` — version bump + tag + CHANGELOG, stops short of pushing (so you'd run `/cut-release` then `/push-close`).
- `/ci-merge` — PR-side auto-merge flow; different surface (PRs, not direct main pushes).
