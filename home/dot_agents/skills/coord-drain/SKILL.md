---
name: coord-drain
description: Drain the running session's coord inbox, pretty-print every message with sender + kind + subject + body (flagging hypervisor replies and worker status updates), run `coord heartbeat` to keep the session alive, and optionally schedule itself as a recurring cron via CronCreate. Use when the user says "drain my inbox", "check for messages", "any replies from the hypervisor", or "what did the workers send back". Args — optional `--loop <interval>` to schedule recurring drain, `--filter <role>` (hypervisor/worker/sentinel) to only surface a specific peer role, `--filter-kind <kind>` to only show one kind, `--no-heartbeat` to skip the keepalive, `--raw` to dump JSON, `--max-body <N>` to truncate long bodies, and optional positional worker session IDs to highlight in output.
---

# coord-drain — drain inbox + heartbeat + pretty-print

Drain the current session's coord inbox in one shot, pretty-print every message before it's lost, keep the session alive with a heartbeat, and (optionally) reschedule itself as a recurring cron. Built around the "I'm a hypervisor or worker waiting on async replies and don't want to manually `coord recv --drain | jq` every time" case.

## When to use

- User asks to "drain my inbox", "check for messages", "any replies", "what did the workers say", "see the hypervisor's response"
- A session is acting as hypervisor coordinating workers and needs to surface incoming `approve` / `deny` / `status` / `accept` / `decline` messages
- A worker session is waiting on a `request` from the hypervisor and wants to peek the inbox without losing the message
- The session has been idle and needs both a heartbeat (so peers see it as live) and an inbox sweep at the same time

**Don't** use this when:
- You want to look at *another* peer's inbox — this skill only drains your own. Use `coord peers` + read `/tmp/claude-coord/messages/inbox-<id>/` directly with the Read tool if you need to inspect (not drain) someone else's queue.
- You want a continuous in-conversation polling loop — that burns tokens. Use `--loop <interval>` to schedule via CronCreate instead of a bash `while true`.
- You only want to peek, not drain — `coord recv --drain` is destructive. There's no peek mode in this skill; use `ls /tmp/claude-coord/messages/inbox-<self>/` + Read directly.

## Procedure

### 1. Parse args

- `--loop <interval>` (e.g. `--loop 1m`, `--loop 5m`, `--loop 30s`): after the drain, schedule a recurring re-run of this skill via `CronCreate` using the `loop` skill's interval translation table. Interval grammar matches `/loop`: `30s`, `1m`, `5m`, `15m`, `1h`, etc.
- `--filter <role>`: only surface messages from senders whose session record has `.role == <role>`. Valid roles: `hypervisor`, `worker`, `sentinel`. Other messages are still drained (the inbox is destructive) but printed in a collapsed `(filtered: N)` line at the end so nothing is silently lost.
- `--filter-kind <kind>`: only show messages of a specific kind. Valid kinds: `approve`, `deny`, `status`, `request`, `accept`, `decline`, `ping`, `pong`, `squawk`, `announce`. Same collapsed-tail rule as `--filter`.
- `--no-heartbeat`: skip the heartbeat step. Default is to always heartbeat — keeping the session alive is the whole point of pairing it with the drain.
- `--raw`: dump raw JSON for each message instead of pretty-printing. Useful for piping into `jq` or copying into a bug report.
- `--max-body <N>`: truncate message bodies longer than N chars to `<first N chars>… (truncated, full body N total)`. Default: no truncation.
- Positional args: session IDs of "known workers" (e.g. `claude-pid-65852 claude-pid-65867`). Messages from these IDs are highlighted with a `[WORKER]` tag even if `--filter` would otherwise hide them. Hypervisor messages are auto-tagged `[HYPERVISOR]` based on the sender's `.role` field.

### 2. Resolve self session ID

```bash
SELF=$(~/.claude/bin/coord whoami 2>/dev/null | jq -r '.session_id')
if [ -z "$SELF" ] || [ "$SELF" = "null" ]; then
  echo "ERROR: coord whoami returned no session_id — is the session registered? Run: coord register --task '<desc>'"
  exit 1
fi
```

If the coord binary is missing entirely, fail loudly:

```bash
test -x ~/.claude/bin/coord || { echo "ERROR: coord binary missing at ~/.claude/bin/coord"; exit 1; }
```

### 3. Heartbeat (unless `--no-heartbeat`)

```bash
~/.claude/bin/coord heartbeat >/dev/null || echo "WARN: heartbeat failed (continuing)"
```

The heartbeat is best-effort — a failure here shouldn't block the drain, because the inbox messages are the load-bearing part.

### 4. Drain the inbox

```bash
RAW=$(~/.claude/bin/coord recv --drain 2>&1)
if [ $? -ne 0 ]; then
  echo "ERROR: coord recv --drain failed:"
  echo "$RAW"
  exit 1
fi
```

`coord recv --drain` returns a JSON array (possibly empty). It is **destructive** — once this returns, those messages are gone from the inbox. The skill MUST print them before returning.

### 5. Pretty-print

If the array is empty:

```
inbox empty
```

(exact string, no decoration — easy to grep for.)

Otherwise, for each message in order:

1. Look up the sender's role:
   ```bash
   ROLE=$(jq -r '.role // .blob.role // "unknown"' \
     "/tmp/claude-coord/sessions/${FROM}.json" 2>/dev/null || echo "unknown")
   ```
   The `// .blob.role` fallback handles pre-TOD-430 records where role lived under `.blob`.

2. Apply `--filter` and `--filter-kind`. If a message is filtered out, increment a counter but don't print it (it's already been drained — the count is surfaced at the end).

3. Determine the tag:
   - `[HYPERVISOR]` if `ROLE == hypervisor`
   - `[WORKER]` if `ROLE == worker` OR sender is in the positional known-workers list
   - `[SENTINEL]` if `ROLE == sentinel`
   - `[unknown role: <role>]` otherwise

4. Print:
   ```
   [TAG] from=<from_session_id> kind=<kind> subject=<subject> sent_at=<sent_at>
     <body, indented 2 spaces, truncated per --max-body>
   ---
   ```

   If `--raw`, print the original JSON object instead (still followed by `---`).

### 6. Optionally schedule recurring drain

If `--loop <interval>` was passed, after the drain prints, call `CronCreate` with:

- `schedule`: translated from the interval per the `loop` skill's table (`30s` → `*/30 * * * * *` if cron supports seconds, else round up to `1m`; `5m` → `*/5 * * * *`; `1h` → `0 * * * *`)
- `prompt`: `Run /coord-drain with the same flags this cron was created with (excluding --loop). Heartbeat the session and print any new inbox messages.`
- `name`: `coord-drain-<self>`

Refuse to double-schedule: if `CronList` already shows a cron with that name, print `cron already scheduled — skipping` and don't recreate.

### 7. Report

Final line, always printed:

```
drained <N> messages (<X> hypervisor, <Y> worker, <Z> other), heartbeat <ok|skipped|failed>, filtered <F>
```

If `--loop` scheduled a cron, append `, cron <name> @ <interval>`.

## Example

Invocation:

```
/coord-drain --filter hypervisor --max-body 200 claude-pid-65852 claude-pid-65867
```

Output:

```
[HYPERVISOR] from=claude-pid-35782 kind=approve subject=PR-19 review sent_at=2026-04-07T18:44:12Z
  Approved with notes — please run /impeccable:audit before merge, target ≥16/20. The harness explainer
  copy on line 47 needs the "Vexwobble" footnote restored. Otherwise ship it.… (truncated, full body 412 total)
---
[HYPERVISOR] from=claude-pid-35782 kind=request subject=swap reveried sent_at=2026-04-07T18:51:03Z
  New TOD-431 fix is on origin/main. Please run /reveried-swap origin/main when you have a clean window —
  no rush, the current binary is correct, just slow on /context/smart.
---
drained 4 messages (2 hypervisor, 2 worker, 0 other), heartbeat ok, filtered 2
```

(The two `[WORKER]` messages from `claude-pid-65852` and `claude-pid-65867` were drained but filtered out by `--filter hypervisor`; they're counted in `filtered 2`.)

## Safety invariants

- **Never** silent-drop a drained message. `coord recv --drain` is destructive — every message MUST be either printed in full, printed as a `[FILTERED]` summary line, or written to a fallback log under `/tmp/claude-coord/drain-log/<self>-<timestamp>.json` if the print itself fails.
- **Never** touch other peers' inboxes. Only `/tmp/claude-coord/messages/inbox-<self>/` is in scope. Reading another peer's session record JSON for role lookup is fine; reading or deleting their inbox is not.
- **Never** skip the heartbeat by default. The skill exists precisely because draining + heartbeating belong together — opt out only when the caller explicitly passes `--no-heartbeat`.
- **Always** fail loudly if the coord binary is missing or `coord whoami` returns no session ID. A silent no-op here means a hypervisor thinks workers are unreachable when really the skill is broken.
- **Always** print `inbox empty` (exact string) when the drain returns zero messages, so callers can grep for it.
- **Never** double-schedule the recurring cron. Check `CronList` first.

## Common pitfalls (from production)

These are real failures observed in sentinel ticks 1-12 of the 2026-04-07 mesh session. The skill's defaults are designed to avoid all of them, but ad-hoc bash drains that bypass the skill have hit each one.

### Pitfall 1: drain only captures `subject`, loses `body`

**What happens**: ad-hoc `coord recv --drain | jq -r '.[] | "from=\(.from_session_id) subject=\(.subject)"'` captures the subject only. Once `--drain` removes the message from the inbox, the body is gone forever.

**Real cost**: 6 important message bodies destroyed in sentinel tick 2 alone (the reviewer's PR #39/#40 verdicts had to be recovered from `gh pr view --comments`; the dashboard-manager's telemetry envelope schema was lost entirely until re-pinged).

**Skill default**: this skill's jq filter ALWAYS includes `.body` and the `--max-body` flag defaults to "no truncation". Use the skill, not ad-hoc bash, and you'll never hit this.

**Engram trace**: see observation `coord/bugs/permission-denied-trace` for the broader pattern of ephemeral-content loss.

### Pitfall 2: drain runs but subscribers go stuck because of bootstrap-only-loop bug

**What happens**: a peer's bootstrap calls `coord recv --drain` once on first turn but never again because the bootstrap doesn't include a `CronCreate` for self-trigger. The peer sits idle forever unless externally nudged.

**Real cost**: claude-pid-41038 (archivist) was stuck for 71 minutes before sentinel intervention.

**Skill default**: the `--loop <interval>` flag schedules a recurring re-run via CronCreate. ALWAYS use `--loop` if the calling session is meant to be a long-running peer. The cron is the "next turn" trigger that bootstrap-only loops lack.

**Engram trace**: `coord/bugs/bootstrap-only-loop-stuck` (root cause) + `coord/patterns/wakeup-chain-for-stuck-peers` (recovery via tmux send-keys).

### Pitfall 3: drain runs successfully but the recipient never reads its own activity log

**What happens**: a peer drains its inbox + processes messages but never `mem_save`s an activity record. From the outside, the peer looks idle.

**Real cost**: silent peers are indistinguishable from dead peers in sentinel audits. Wasted ping cycles.

**Skill default**: the report line at the end (`drained N messages, heartbeat ok`) is the minimum activity record. Calling sessions should ALSO `mem_save` a `coord/activity/<role>/tick-<ts>` observation as part of their tick to leave a durable trail.

## Related observations (production engram trace)

| Engram obs | Topic key | Description |
|---|---|---|
| #374 | `coord/bugs/permission-denied-trace` | Full classification of permission-denied error classes A/B/C |
| #377 | `coord/bugs/bootstrap-only-loop-stuck` | Root cause of stuck Claude sessions whose bootstrap-only loop never fires past first turn |
| #380 | `coord/patterns/wakeup-chain-for-stuck-peers` | Validated 8-step recovery chain via tmux send-keys (verified end-to-end with archivist wakeup at tick 12) |
| #343 | `coord/role-registry` | Canonical 15-role registry (upserted across mesh growth) |

These are the ground-truth references for the patterns this skill defends against. Future sentinels should mem_search for them on first invocation.

## Future extensions

- **Peek mode** — non-destructive `ls /tmp/claude-coord/messages/inbox-<self>/` + Read each file, no `--drain`. Useful for "show me what's queued without consuming it" workflows. Blocked on a `coord recv --peek` flag landing in the binary.
- **Auto-route by kind** — `approve` / `deny` could auto-update a Linear ticket; `status` from a worker could auto-update a TodoWrite item. Probably belongs in a separate `coord-route` skill that this one calls.
- **Per-sender rate display** — track how often each peer sends and surface "claude-pid-65852 has sent 14 messages in the last hour" so the hypervisor can spot a runaway worker.
- **Backpressure signal** — if inbox depth crosses a threshold (e.g. 50 messages), automatically `coord send` a `pause` request to the noisiest sender. Needs sender-side honoring of pause to be useful.
- **Replay log** — write every drained message to `~/.claude/coord/drain-history/<self>.jsonl` so you can `tail -f` the history without touching the inbox. Bounded by daily logrotate.
