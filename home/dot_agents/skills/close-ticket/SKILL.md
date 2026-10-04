---
name: close-ticket
description: Mark a Linear issue Done with evidence, through `linearctl`. The shipping comment (commit SHA, or another named verification) lands FIRST, then the state flip, then a re-read confirms the close. Never the Linear MCP; never a close without evidence. Use when the user says "close CER-X", "mark X done, shipped in abc1234", "wrap up OPS-Y with commit Z", or after a push lands a fix for a tracked ticket. Args — `<ISSUE-ID>` required, `<commit-sha>` required (short or full), optional `--note "<extra context>"` appended to the shipping comment.
---

# close-ticket — evidence comment, then Done, then re-read

Close one Linear ticket with the standard shipping record. **v2 (2026-10-04):**
rewritten onto `linearctl` (never the Linear MCP for writes), the TaskUpdate
coupling is removed, and any team identifier (`CER-123`, `OPS-456`, …) works —
the old TOD-only wording is gone.

## When to use

- "close CER-731", "mark OPS-12 done, shipped in abc1234", "wrap up EST-88"
- A commit has just landed on main that resolves a tracked ticket
- Inside `/push-close` as the per-ticket inner loop

## When NOT to use

- The fix isn't on main yet — push first
- Only one part of a multi-part epic shipped — comment, don't flip state
- Close as Cancelled / Won't Fix — `linearctl update <id> --state Canceled`
  directly, with a comment saying why
- No evidence exists — a close **requires** evidence: a merged commit/PR, all
  children done, or a live check named in the comment

## Preconditions

```bash
linearctl --version   # >= 0.7.0
linearctl whoami      # abort on auth failure, no retry
linearctl ratelimit   # abort below 300 remaining
```

## Procedure

### 1. Parse args / preflight

- `<ISSUE-ID>` (positional, required): must match `^[A-Z]+-[0-9]+$`.
- `<commit-sha>` (positional, required): short (7+) or full hex. Verify it
  resolves in the relevant repo **before** touching Linear:

  ```bash
  git -C <repo> rev-parse --verify "${SHA}^{commit}" >/dev/null \
    || { echo "ERROR: SHA ${SHA} does not resolve in <repo>"; exit 1; }
  SHORT="$(git -C <repo> rev-parse --short=7 "$SHA")"
  ```

- `--note "<text>"` (optional): appended to the shipping comment.

Read the ticket first: `linearctl show <ID> --json`. If it is already in a
completed state (`stateType: completed`), post the comment if there is
something new to record and stop — never re-flip.

### 2. Comment FIRST (evidence before close)

The shipping record lands as a comment *before* the state transition — a close
without its evidence comment is the failure mode this ordering prevents
(estate convention; see `linear-groom` "closes need evidence"):

```bash
linearctl comment <ID> --body - <<'EOF'
Shipped in `<short-sha>` on main.

<optional --note text>
EOF
```

Body is piped on stdin (`--body -`), never via shell-escaped arguments.

### 3. Flip state

```bash
linearctl close <ID> --json
```

Nothing else on this call — no title, description, or label edits ride along.

### 4. Re-read and report

Confirm with a different call than wrote it:

```bash
linearctl show <ID> --json   # assert stateType == "completed"
```

Report one line:

```
CER-731 → Done (shipped in abc1234)
```

or, when step 1 found it already closed: `<ID> already Done — comment appended
only`.

If the re-read shows the state did NOT land, say so loudly and stop — do not
retry blindly; surface `linearctl history <ID> --json` for the operator.

## Safety invariants

- Writes through `linearctl` only — never the Linear MCP; never a ticket ID in
  an MCP comment body (`hold-batch-ops-until-root-cause.md`).
- Evidence first: the comment naming the commit lands before the state flip.
- Never close against a SHA that doesn't resolve locally — `rev-parse --verify`
  is mandatory.
- Never close without evidence. The SHA is the default evidence; a close with
  different evidence (children done, live check) names it in the comment
  instead — but a bare close is always wrong.
- One ticket per invocation; batch closes are `/push-close` or
  `linearctl update --stdin --apply` with a plan you wrote.

## Examples

```
close-ticket CER-725 a4f2c19
close-ticket OPS-730 f8b2001 --note "ACK now precedes execute; see src/worker.rs:142"
```

## Example script

`scripts/close-ticket-example.sh <ID> <sha> [--note text]` — runs the full
verify-SHA → comment → close → re-read sequence against a real ticket.

## Related skills

- `/push-close` — push main and close every ticket named in commit messages
- `/file-bug` — open a new bug with the standard template
- `/linear-file-spec` — multi-section spec filing
