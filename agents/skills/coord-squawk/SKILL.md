---
name: coord-squawk
description: Broadcast a kind=squawk coord message to every known session inbox (live + stale) and wait for replies. Used when the live-peer list is empty but queued session records may still be reachable, or when the user asks "anyone alive?", "squawk for a hypervisor", "broadcast ping", or "find who can X". Args — `<subject>` and `<body>` (both required), optional `--target-role <role>`, `--wait <seconds>` (default 30, max 120), `--live-only`, `--dry-run`.
---

# coord-squawk — fan-out broadcast to coord peers

Broadcast a `kind=squawk` message to every session record under `/tmp/claude-coord/sessions/` (except self), optionally filtered by role, then wait N seconds and drain the local inbox for replies. Encapsulates the "iterate session records in a for-loop" pattern so future sessions don't have to reinvent it.

## When to use

- `coord peers --live` returns empty but there are session records in `/tmp/claude-coord/sessions/` that might still be reachable
- User says "squawk for a hypervisor", "anyone out there", "broadcast ping", or "find who can X"
- Fallback after `coord peers --live --cap <capability>` returns no matches
- Need to solicit role-specific identification (hypervisor pong, sentinel ack) from unknown set of peers

**Don't** use when:
- There are ≥3 live peers and the target is known — just `coord send` directly
- You need a heartbeat — that's `coord heartbeat`
- You need structured RPC request/reply — that's the upcoming work queue (TOD-438)
- The body would contain anything secret-looking

## Procedure

### 1. Parse args

- `<subject>` (required positional) — squawk subject line
- `<body>` (required positional) — squawk body
- `--target-role <role>` — only send to sessions whose record has that role (`hypervisor`, `worker`, `sentinel`). Default: all except self
- `--wait <seconds>` — how long to wait before draining (default 30, max 120, floor 5)
- `--live-only` — skip stale sessions (no heartbeat in last 300s)
- `--dry-run` — print send list + body, do not actually send

### 2. Pre-flight safety checks

Refuse if any of the following are true:

- `len(body) > 8192` → abort with "squawk body exceeds 8 KB limit"
- A previous squawk was sent in the last 60s (check `/tmp/claude-coord/.last-squawk-ts` mtime) → warn and abort
- `subject` or `body` matches `/(KEY|TOKEN|SECRET|PASSWORD|CRED)/i` → abort with "refusing to broadcast secret-shaped content"

On pass, touch `/tmp/claude-coord/.last-squawk-ts` to arm the rate limit (do this *after* validation, *before* sending).

### 3. Identify self

```bash
SELF=$(~/.claude/bin/coord status 2>/dev/null | grep -oP 'session_id["[:space:]:]+\K[^"[:space:],]+' | head -1)
```

Never send to `$SELF`. If `$SELF` is empty, warn but proceed (treat all records as non-self).

### 4. Find target sessions

```bash
NOW=$(date +%s)
TARGETS=()
for f in /tmp/claude-coord/sessions/*.json; do
  [ -f "$f" ] || continue
  sid=$(jq -r '.session_id' "$f")
  [ "$sid" = "$SELF" ] && continue

  # Role filter — top-level first, fall back to .blob.role for pre-TOD-430 records
  if [ -n "$TARGET_ROLE" ]; then
    role=$(jq -r '.role // .blob.role // empty' "$f")
    [ "$role" = "$TARGET_ROLE" ] || continue
  fi

  # Liveness filter
  if [ "$LIVE_ONLY" = "1" ]; then
    hb=$(jq -r '.last_heartbeat // 0' "$f")
    age=$(( NOW - hb ))
    [ "$age" -le 300 ] || continue
  fi

  TARGETS+=("$sid")
done
```

Report count + list. If zero, abort cleanly: "no matching session records; nothing to squawk".

### 5. Dry-run exit

If `--dry-run`, print the send list, subject, body, and return without calling `coord send`.

### 6. Send

```bash
SENT=0
FAILED=0
for sid in "${TARGETS[@]}"; do
  if ~/.claude/bin/coord send "$sid" squawk "$SUBJECT" --body "$BODY" 2>/dev/null; then
    SENT=$((SENT+1))
  else
    FAILED=$((FAILED+1))
  fi
done
```

### 7. Wait

```bash
# Floor of 5s gives filesystem-mkdir atomic writes time to land
SLEEP=$WAIT
[ "$SLEEP" -lt 5 ] && SLEEP=5
[ "$SLEEP" -gt 120 ] && SLEEP=120
sleep "$SLEEP"
```

### 8. Drain inbox

```bash
REPLIES=$(~/.claude/bin/coord recv --drain 2>/dev/null)
```

Parse the JSON array. For each message, extract `from`, `kind`, `subject`, `body`. Classify:

- **Hypervisor identification** — `kind` in {`pong`, `identify`} AND sender's session record has `role=hypervisor`
- **Approval** — `kind=approve`
- **Denial** — `kind=deny`
- **Work assignment** — `kind` in {`assignment`, `request`} AND `subject` contains a TOD-ID (`/TOD-\d+/`)
- **Other** — everything else, listed but not flagged

### 9. Report

Print:

- Squawks sent: `<SENT>` (failed: `<FAILED>`)
- Targets: `<count>` (filter: `<role or "all">`, liveness: `<live-only or "all">`)
- Wait: `<SLEEP>s`
- Replies received: `<count>`
- Matched hypervisors: `<count>` — list `session_id / claude_pid / capabilities[]`
- Approvals: `<count>`, Denials: `<count>`, Assignments: `<count>`
- Timestamps: sent-at / drained-at

## Safety invariants

- **Never** send a squawk with body > 8 KB. Novels don't belong in broadcasts.
- **Never** squawk more than once per 60s. Rate-limited via `/tmp/claude-coord/.last-squawk-ts`.
- **Never** include secrets. Pattern-match `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*CRED*` in subject and body, refuse on match.
- **Always** sleep at least 5 seconds before draining, regardless of `--wait`, so atomic-write inbox deliveries have time to land.
- **Never** delete or modify peers' session records while scanning.
- **Never** send to self — always resolve `$SELF` from `coord status` first.

## Example invocations

```bash
# Broadcast-style ping for a hypervisor
/coord-squawk "seeking hypervisor" "please identify if you can approve PRs" --target-role hypervisor --wait 30

# Open-ended "anyone alive?"
/coord-squawk "ping" "session X checking who's around" --wait 15

# Preview without sending
/coord-squawk "test" "dry run" --dry-run

# Live peers only, short wait
/coord-squawk "capability check" "who has cargo-build?" --live-only --wait 10
```

## Background

The pattern was first hand-rolled in a session that needed to find a hypervisor when `coord peers --live` returned empty — a for-loop over `/tmp/claude-coord/sessions/*.json` sending to each `session_id` found `claude-pid-35782` as the live hypervisor. This skill encapsulates that loop plus the safety rails (rate limit, secret guard, body cap) so it can be invoked as a single command.

## Future extensions

- **TOD-438 work queue** — once structured RPC request/reply lands, squawk becomes a fallback only for discovery; all real work uses the queue
- **Reply correlation IDs** — attach a nonce to the squawk and filter drained replies by it, so concurrent squawks don't cross-pollinate
- **Session-record freshness re-scan** — after sending, re-read target records to see if any heartbeat advanced, as a second liveness signal beyond the inbox reply
