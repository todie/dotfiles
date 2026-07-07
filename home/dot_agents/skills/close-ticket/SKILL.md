---
name: close-ticket
description: Mark a Linear issue Done and append a comment recording the shipping commit SHA, plus sync any matching TaskList entry. Always the same 2–3 MCP calls — save_comment with the SHA note, save_issue flipping state to Done, then TaskUpdate for any task with metadata.linear matching the TOD-ID. Use when the user says "close TOD-X", "mark X done, shipped in abc1234", "wrap up TOD-Y with commit Z", or after a push lands a fix for a tracked ticket. Args — `<TOD-ID>` required, `<commit-sha>` required (short or full), optional `--note "<extra context>"` appended to the shipping comment.
---

# close-ticket — flip Linear issue to Done + log shipping SHA

Close one Linear ticket with the standard shipping record: a comment citing the commit SHA on main, a state transition to Done, and a TaskList sync if a task tracks this TOD. Built for the "I just pushed the fix, close the ticket" moment that otherwise sprawls into 4 manual MCP calls.

## When to use

- User says "close TOD-731", "mark TOD-X done, shipped in abc1234", "wrap up TOD-Y"
- A commit has just landed on main that resolves a tracked ticket
- Inside `/push-close` as the per-ticket inner loop

## When NOT to use

- The fix isn't actually on main yet — wait for `git push` to succeed first.
- The ticket is a multi-part epic where only one part shipped — add a comment instead, don't flip state.
- You want to close as "Cancelled" / "Won't Fix" — use the Linear MCP directly with the right state.
- You want to close many tickets after one push — use `/push-close` which batches this skill.

## Procedure

### 1. Parse args / preconditions

- `<TOD-ID>` (positional, required): e.g. `TOD-731`. Must match `^TOD-\d+$`.
- `<commit-sha>` (positional, required): short (7+) or full hex SHA. Validated with `git rev-parse --verify <sha>^{commit}` — refuse if unknown to the local repo.
- `--note "<text>"` (optional): appended to the shipping comment after a blank line.

Preflight:
- Confirm `mcp__claude_ai_Linear__*` tools are available.
- Confirm the SHA resolves locally (prevents typos closing tickets against a non-existent commit):
  ```bash
  git -C ~/projects/reverie rev-parse --verify "${SHA}^{commit}" >/dev/null \
    || { echo "ERROR: SHA ${SHA} does not resolve in reverie repo"; exit 1; }
  ```
- Short-form the SHA to 7 chars for display: `SHORT=$(git rev-parse --short=7 "$SHA")`.

### 2. Post the shipping comment

Call `mcp__claude_ai_Linear__save_comment`:

- `issueId`: `<TOD-ID>`
- `body`:
  ```markdown
  Shipped in `<SHORT>` on main.

  <optional --note text>
  ```

Send real newlines (per the claude_ai_Linear MCP instruction), not `\n` escapes. Omit the trailing blank line + note section if `--note` wasn't given.

### 3. Flip state to Done

Call `mcp__claude_ai_Linear__save_issue`:

- `id`: `<TOD-ID>`
- `state`: `Done`

Do NOT pass title / description / labels — this is a pure state transition and sending other fields risks clobbering them.

### 4. Sync TaskList (if applicable)

Check the current session's TaskList for any task where `metadata.linear == "<TOD-ID>"`. If one exists, `TaskUpdate` it to `status: completed`.

If no matching task is found, skip this step silently — not every Linear ticket has a local task.

### 5. Report

One line:

```
TOD-731 → Done (shipped in abc1234)
```

If a TaskList entry was also synced, append ` + task synced`.

If the ticket was already Done before this call (detected by reading the current state via `get_issue` beforehand, or by Linear returning a no-op), report `TOD-731 already Done — comment appended only`.

## Examples

```
/close-ticket TOD-725 a4f2c19
```

Posts "Shipped in `a4f2c19` on main." comment, flips TOD-725 to Done.

```
/close-ticket TOD-730 f8b2001 --note "ACK is now before execute; see crates/reveried/src/worker.rs:142"
```

Posts a comment with the SHA and the extra context note, flips to Done.

## Safety invariants

- Never close a ticket against a SHA that doesn't exist locally. The `rev-parse --verify` check is mandatory.
- Never pass title/description/labels on the state-transition `save_issue` call — it will silently overwrite.
- Always short the SHA to 7 chars for the comment (Linear renders long SHAs as ugly walls of text).
- Use real newlines in comment body, not escape sequences.

## Related skills

- `/push-close` — push main and close every TOD-ID mentioned in commit messages in one shot (calls this skill internally).
- `/file-bug` — open a new bug with the standard template.
- `/linear-file-spec` — multi-section spec filing.
