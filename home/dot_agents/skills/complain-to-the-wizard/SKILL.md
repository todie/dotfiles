---
name: complain-to-the-wizard
description: Send a complaint, bug report, question, or unix-philosophy audit request to the wizard role (14th canonical coord role, tmux-backed, owns POSIX/shell/idiom audits). Discovers the wizard's current session_id via `coord peers`, formats as SYM/0 frame, sends via `coord send`, and falls back to an engram `mem_save` under topic_key `coord/inbox/wizard/<ts>` if the wizard is offline. Use when you hit a shell/script/POSIX/idiom question, a systems-level weirdness, a `bash` vs `sh` portability snag, a tmux oddity, or a unix-philosophy critique you want weighed. Args — the complaint body (required), optional `--urgent` flag for kind=urgent escalation, optional `--kind <k>` to override the default kind=request.
---

# complain-to-the-wizard

The wizard is the 14th canonical coord role (per `engram:coord/header/01-roles`), spawned by the mesh in late 2026-04-07 as a tmux-backed peer with management authority for **unix-philosophy audits, POSIX-pure idioms, shell scripting reviews, and systems-level debugging**. If you're doing anything shell/script/tmux/POSIX and want a second opinion from the lane that actually cares, send it to the wizard.

## When to use

- You hit a `bash` vs `sh` portability snag and want the POSIX-correct form
- You wrote a shell pipeline you're not sure is idiomatic
- You're about to reach for Python when `awk`/`jq`/`sed` would do — and want sanity-checked
- You have a tmux layout, keybinding, or session weirdness
- You built a docker-compose-equivalent via `docker run` calls and want a review
- You want the wizard's opinion on `llm-task` router patterns (Phase 2 / TOD-487)
- Anything you'd write to `#unix-philosophy` in a chat and expect opinionated answers

**Don't** use for:
- Tickets / tracking — that's the curator (`curator` role)
- PR reviews — that's the reviewer (`reviewer` role)
- Design docs — keep those in prose, not coord
- Metrics / observability — that's telemetry-stack-owner (you, probably)
- Urgent outages — use kind=urgent directly via `coord send`, don't route through this skill

## Procedure

### 1. Parse args

- Positional arg: the complaint body text. Required. Can be multi-line. If the first char is `@`, read from a file path.
- `--urgent`: bump kind from `request` to `urgent`, add a `!urgent` tag to the SYM/0 frame
- `--kind <k>`: override the kind entirely (one of: `request`, `question`, `advice`, `review`, `urgent`)
- `--subject <str>`: override the auto-generated subject (default: first 60 chars of body)

### 2. Discover the wizard

Use `coord peers` to find the current wizard session. The wizard's pid flips as they reincarnate — don't hardcode:

```bash
WIZARD=$(~/.claude/bin/coord peers 2>/dev/null | python3 -c '
import sys, json, datetime
now = datetime.datetime.now(datetime.timezone.utc)
peers = json.load(sys.stdin)
# Prefer LIVE (hb<15min), then STALE (<1h), fall back to most recent zombie
def age(p):
  return (now - datetime.datetime.fromisoformat(p["last_heartbeat"].replace("Z","+00:00"))).total_seconds()
wizards = [p for p in peers if p.get("role") == "wizard"]
if not wizards:
  print("")
else:
  wizards.sort(key=age)
  print(wizards[0]["session_id"])
')
```

### 3. Build the SYM/0 frame

Per the SYM/0 wire spec (`coord/header/00-sym-v0`):

```
F<n>|@<hhmm>|V<subject-slug>|T<from>→wizard|K<kind>|B<body-first-200-chars>|Nfull-body-in-engram-if-truncated
```

If the body is longer than 800 chars, save the full body to engram under `coord/inbox/wizard/<ts>-<slug>` first, then reference it in the SYM/0 frame with `N=engram-obs-<id>`.

### 4. Send via coord

```bash
if [ -n "$WIZARD" ]; then
  ~/.claude/bin/coord send "$WIZARD" "$KIND" "$SUBJECT" --body "$FRAME"
else
  echo "WARN: no wizard in registry — falling back to engram-only drop"
fi
```

### 5. Engram fallback

Always persist to engram, whether or not the coord send landed. The wizard may boot later and `mem_search` their inbox:

```bash
mcp__plugin_engram_engram__mem_save \
  title="wizard inbox: $SUBJECT" \
  topic_key="coord/inbox/wizard/$(date +%Y%m%d-%H%M%S)-$SLUG" \
  type="manual" \
  project="reverie" \
  content="$FULL_BODY_WITH_SOURCE_AND_SYM_FRAME"
```

### 6. Report

Print a one-line SYM/0 confirmation frame:

```
F<n>|@<hhmm>|Vcomplain-sent|T<self>→wizard|Ksent-and-persisted|Scoord-send=ok|Sengram-obs-<id>|N<subject>
```

If the coord send failed but engram save succeeded, use `Scoord-send=offline|Sengram-obs-<id>` so the caller knows the wizard will only see it on their next mem_search.

## Safety invariants

- **Never** spam the wizard — this skill is for ONE complaint per call. Don't loop.
- **Never** bypass engram — always save, even on successful coord send. The wizard may lose their session state and need to recover via mem_search.
- **Never** use this skill for urgent outages — those go direct to hypervisor via `coord send <hyp> urgent`.
- **Respect the role** — the wizard owns POSIX/shell/unix-philosophy. Don't dump Rust code or design RFCs on them; they're not a catch-all channel.
- **Body > 800 chars → engram first, frame references.** SYM/0 frames should stay under ~800 chars; anything longer truncates in the coord inbox and loses signal.

## Common invocations

```
# POSIX portability check
/complain-to-the-wizard "this bash pipeline uses process substitution, is there a POSIX-pure equivalent?  <(cat a) <(cat b) | diff"

# tmux layout review
/complain-to-the-wizard --kind review "my spawn-role-peer.sh uses tmux new-session -d -s and the session dies on first enter — is there a prompt that doesn't need an interactive tty?"

# idiom audit
/complain-to-the-wizard "I wrote python3 -c 'import json; d=json.load(...)' in a shell script to parse JSON. jq would fit but this script runs in alpine minimal. Is there a pure-sh way that isn't awful?"

# from a file
/complain-to-the-wizard @/tmp/weird-output.log --subject "why is this strace sequence weird"
```

## Fallback if coord is offline

If `~/.claude/bin/coord` fails entirely, the skill still saves to engram under `coord/inbox/wizard/<ts>-<slug>` and reports `offline`. The wizard scans their inbox topic on boot so nothing is lost.
