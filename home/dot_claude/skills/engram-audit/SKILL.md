---
name: engram-audit
description: >
  Health-check the engram memory store. Reports DB size, total observations +
  sessions, top projects by obs count, type distribution, topic-key prefixes,
  duplicate topic keys, orphaned sessions, soft-deleted rows, broken
  supersession links, and the largest single observations. Read-only — safe to
  run anytime. Use when the user says "audit engram", "check memory", "what's
  up with engram", or after a long session before running /engram-cleanup.
allowed-tools:
  - Bash
tags: [engram, memory, audit, smoke-check]
---

# Engram audit

Read-only health report over `~/.engram/engram.db`. Does not mutate, does not
require stopping reveried.

## Steps

1. Confirm reveried is up: `curl -sf http://127.0.0.1:7437/health | jq`
2. Run the audit python block (inline — no file on disk):

```bash
python3 - <<'PY'
import sqlite3, os
db = sqlite3.connect("/home/ctodie/.engram/engram.db")
def q(sql, label):
    print(f"--- {label} ---")
    cur = db.execute(sql)
    cols = [d[0] for d in cur.description]
    print(" | ".join(cols))
    for r in cur.fetchall(): print(" | ".join(str(x) for x in r))
    print()
q("SELECT project, COUNT(*) n FROM observations GROUP BY project ORDER BY n DESC LIMIT 15", "top projects by obs count")
q("SELECT type, COUNT(*) n FROM observations GROUP BY type ORDER BY n DESC", "type distribution")
q("SELECT substr(topic_key,1,instr(topic_key||'/','/')-1) prefix, COUNT(*) n FROM observations WHERE topic_key IS NOT NULL GROUP BY prefix ORDER BY n DESC LIMIT 20", "topic-key prefixes")
q("SELECT topic_key, COUNT(*) n FROM observations WHERE topic_key IS NOT NULL GROUP BY topic_key HAVING n>10 ORDER BY n DESC LIMIT 20", "duplicate topic keys (>10)")
q("SELECT COUNT(*) n FROM sessions s WHERE NOT EXISTS (SELECT 1 FROM observations o WHERE o.session_id=s.id) AND NOT EXISTS (SELECT 1 FROM user_prompts u WHERE u.session_id=s.id)", "orphaned sessions (no obs, no prompts)")
q("SELECT COUNT(*) n FROM observations WHERE deleted_at IS NOT NULL", "soft-deleted obs (reclaimable)")
q("SELECT COUNT(*) n FROM observations WHERE supersedes IS NOT NULL AND supersedes NOT IN (SELECT sync_id FROM observations WHERE sync_id IS NOT NULL)", "broken supersession links")
q("SELECT COUNT(*) n FROM observations WHERE type IS NULL OR type=''", "obs with empty type")
q("SELECT id, project, type, length(content) bytes, substr(title,1,60) title FROM observations ORDER BY bytes DESC LIMIT 5", "largest single observations")
q("SELECT COUNT(*) total_obs FROM observations", "total obs")
q("SELECT COUNT(*) total_sessions FROM sessions", "total sessions")
print(f"DB size: {os.path.getsize('/home/ctodie/.engram/engram.db')/1024/1024:.1f} MB")
PY
```

3. Summarize findings + flag any cleanup opportunities.

## Cleanup triggers

- **Bench-run pollution**: projects matching `bench-reveried-%` → run /engram-cleanup
- **>500 orphaned sessions** → run /engram-cleanup
- **Soft-deleted obs >10% of total** → run /engram-cleanup (for VACUUM reclamation)
- **Broken supersession links >0** → run /engram-cleanup
- **Obs with empty type >0** → run /engram-cleanup

## Do NOT

- Mutate the DB from this skill (read-only).
