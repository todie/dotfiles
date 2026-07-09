# SPEC / HANDOFF → dotfiles session — global process-termination guard

**From:** unsigned-paas session (pid 38236), 2026-06-02
**To:** dotfiles session (pid 84648) — owner of global `~/.claude` config + canonical hooks
**Priority:** high (operator: "really really important, need a resounding fix")
**Why this session is handing it off:** global Claude config / hooks are the dotfiles session's lane.

## Problem (operator's words)

> "Destroying other processes is a no-go without explicit handler approval or request. It's not as simple as just not letting you call `kill`, though, because this is part of your QA and testing suite."

Two failure modes to prevent, simultaneously:
1. **Hard no:** Claude terminating processes it does **not** own — other agent/operator Claude sessions, `reveried`/`engram` daemons, the operator's running work — **without explicit operator approval**. (This session twice *offered* to kill a peer's pid 70998 mid-task; that offer itself is the smell to kill.)
2. **Don't over-correct:** a blanket `kill` ban is wrong — terminating processes is legitimate, frequent QA/test/cleanup behavior: stale-worker cleanup, `reveried-swap` frees busy-binary holders, test harnesses kill spawned servers/children. Those must keep working.

The needle: **block killing what I didn't spawn; allow killing what I did; let the operator explicitly authorize the exceptions.**

## Why the peer registry can't be the basis (proven 2026-06-02)

The existing peer roster is unreliable — it reported a **dead pid (66035) as alive**, missed **6 live sessions**, and its presence is non-deterministic (logged as CER-1114). **Do not build the guard on the peer registry.** The trustworthy liveness surface is `/proc` (kernel ground truth):

```bash
for p in $(pgrep -x claude); do echo "$p $(readlink /proc/$p/cwd)"; done
```

This is how the guard classifies a target pid as "another live session" vs "mine."

## Design — PreToolUse Bash hook, ownership-based, enforced + overridable

**Classification of every termination target:**
- **MINE → allow:** target pid is a descendant of the calling Claude session (walk `/proc/PID/stat` ppid chain to the session root). Covers spawned test servers, background jobs, `%job` specs.
- **FOREIGN → block:** target pid is **not** my descendant — especially if its `comm` is `claude`/`reveried`/`engram`/`node` (another session or daemon). Conservative default: any non-descendant is foreign.

**Override (the "explicit approval" gate):** an inline `# allow-kill-foreign` token, mirroring the existing `# allow-secret-print` / `# allow-direct-push` pattern. With it present, the guard allows + logs the bypass. Claude is instructed to add it **only on the operator's explicit request/approval**, and to surface that it did. This is what keeps the QA/test suite working: the QA skills run *with* the surfaced override.

**Enforcement, not advice** (per the trust-enforcement compact / [[feedback_trust_enforcement_northstar]]): hard block (exit 2), not a warn. The only bypass is the explicit operator-authorized token, and every bypass is logged.

## Reference implementation (turnkey — harden as needed)

`claude/hooks/guard-process-termination.sh`:

```bash
#!/usr/bin/env bash
# guard-process-termination.sh — PreToolUse(Bash). Exit 0=allow, 2=block.
# Blocks terminating processes this session did not spawn (other sessions/
# daemons) unless the operator authorizes via `# allow-kill-foreign`.
set -euo pipefail
INPUT=$(cat); COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Operator override (explicit approval for QA/cleanup kills).
if echo "$COMMAND" | grep -qE '#[[:space:]]*allow-kill-foreign'; then
  echo "NOTE: process-kill guard bypassed via # allow-kill-foreign (operator-approved)." >&2; exit 0; fi

# Termination intent?
echo "$COMMAND" | grep -qE '(^|[^[:alnum:]_])(kill|pkill|killall|kkill)([[:space:]]|$)|fuser[[:space:]].*-k' || exit 0

# Root we may kill beneath = this session's claude pid.
SELF_ROOT="${CLAUDE_SESSION_PID:-}"
if [ -z "$SELF_ROOT" ]; then pid=$$
  while [ "${pid:-1}" -gt 1 ]; do
    [ "$(cat /proc/$pid/comm 2>/dev/null)" = claude ] && { SELF_ROOT=$pid; break; }
    pid=$(awk '{print $4}' /proc/$pid/stat 2>/dev/null || echo 1); done; fi

is_descendant(){ local q=$1; while [ "${q:-1}" -gt 1 ]; do [ "$q" = "$SELF_ROOT" ] && return 0
  q=$(awk '{print $4}' /proc/$q/stat 2>/dev/null || echo 1); done; return 1; }

# Candidate target pids: explicit numerics + pkill/killall pattern matches.
TARGETS=$(echo "$COMMAND" | grep -oE 'kill[[:space:]]+(-[0-9A-Za-z]+[[:space:]]+)?[0-9 ]+' | grep -oE '[0-9]+' || true)
PAT=$(echo "$COMMAND" | grep -oE '(pkill|killall)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]+' | awk '{print $NF}' || true)
[ -n "$PAT" ] && TARGETS="$TARGETS $(pgrep -f -- "$PAT" 2>/dev/null || true)"

BLOCK=""
for t in $TARGETS; do [ -d /proc/$t ] || continue
  is_descendant "$t" && continue
  BLOCK="$BLOCK $t($(cat /proc/$t/comm 2>/dev/null || echo ?))"; done

if [ -n "$BLOCK" ]; then
  echo "BLOCKED: refusing to terminate process(es) this session did not spawn:$BLOCK" >&2
  echo "Killing other sessions/processes needs explicit operator approval." >&2
  echo "If authorized QA/cleanup, append  # allow-kill-foreign  (operator-approved), or ask the operator." >&2
  exit 2; fi
exit 0
```

## Integration checklist (dotfiles session)

- [ ] Land `guard-process-termination.sh` in the canonical hooks dir; `chmod +x` (per [[feedback_hook_exec_bit_check]] — non-exec command hooks fail silent exit 126, and `~/.claude` mode-drifts since it isn't git-tracked; sync from dotfiles).
- [ ] Register as a **PreToolUse** matcher on `Bash` in `settings.json` (alongside `guard-dangerous-commands.sh`, `guard-secret-access.sh`).
- [ ] Export/confirm a `CLAUDE_SESSION_PID` env for the session root if the harness offers one (more robust than ancestry-walk).
- [ ] Decide the agentic layer (operator said "or whatever combination of agentic guards"): keep deterministic hard-block as primary; OPTIONAL secondary = on block, an agentic classifier reads intent and can escalate to the operator. Recommend deterministic-first (enforced > advisory).

## Test plan (kill IS part of the QA suite — must verify both directions)

1. **Own child allowed:** `sleep 300 &` then `kill %1` / `kill <child-pid>` → **allow**.
2. **Foreign session blocked:** `kill <another-claude-pid>` (e.g. a peer session) → **block, exit 2**. (Use a throwaway `sleep` outside the session subtree to simulate.)
3. **Daemon blocked:** `pkill -f reveried` → **block**.
4. **Override works:** `kill <foreign-pid>  # allow-kill-foreign` → **allow + logged** (this is the path `reveried-swap` takes).
5. **No-target commands unaffected:** `git log`, `killall` in help text, etc. → allow.
6. **QA skills** still function when they carry the override.

## Decisions (operator-approved 2026-06-03)

1. **Mechanism → deterministic hard-block + `# allow-kill-foreign` override (LOCKED).** No agentic layer in the kill path — enforced > advisory. Every override use is logged.
2. **Owner → the dotfiles session builds it** (this is a handoff, not an implementation; global `~/.claude` config is your lane).

### Still open (operator's call when you build)
- Whether `# allow-kill-foreign` is sufficient as "explicit approval," or kills of *another live claude session* specifically should require a stronger gate (typed confirmation / second factor) even with the token.
- Whether to also guard non-`kill` termination paths (`systemctl kill`, writing to `/proc/PID`, `docker kill` of non-own containers).
