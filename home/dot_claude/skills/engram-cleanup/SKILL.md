---
name: engram-cleanup
description: >
  Mutating cleanup pass over the engram DB — nukes bench-run pollution
  (bench-reveried-* projects), hard-deletes soft-deleted observations, prunes
  empty sessions (no obs + no prompts), fixes broken supersession links,
  backfills empty `type` columns, then VACUUMs. Takes a timestamped backup
  first and stops reveried for the duration of the write. Use after
  /engram-audit flags cleanup triggers, or when the user says "clean up
  engram", "reclaim space", "purge bench runs".
allowed-tools:
  - Bash
tags: [engram, memory, cleanup, vacuum, destructive]
---

# Engram cleanup

Destructive but always backs up first. Ops are deterministic: bench runs are
throwaway, soft-deleted obs are already gone from the API's view, orphan
sessions are rows with zero references.

## Steps

1. **Backup**:
   ```bash
   cp ~/.engram/engram.db ~/.engram/engram.db.bak-$(date +%Y%m%d-%H%M%S)
   ```

2. **Stop daemon** (required — sqlite write lock):
   ```bash
   systemctl --user stop reveried
   sleep 2 && ! curl -sf http://127.0.0.1:7437/health
   ```

3. **Run the 5-op cleanup + VACUUM**:

```bash
python3 - <<'PY'
import sqlite3, os
db = sqlite3.connect(os.path.expanduser("~/.engram/engram.db"))
db.execute("PRAGMA foreign_keys = ON")
def cnt(s): return db.execute(s).fetchone()[0]
print(f"PRE: obs={cnt('SELECT COUNT(*) FROM observations')} sessions={cnt('SELECT COUNT(*) FROM sessions')}")

# 1. Nuke bench-reveried-* projects (FK-safe order)
ids = [r[0] for r in db.execute("SELECT id FROM sessions WHERE project LIKE 'bench-reveried-%'")]
if ids:
    ph = ",".join("?"*len(ids))
    db.execute(f"DELETE FROM user_prompts WHERE session_id IN ({ph})", ids)
n1 = db.execute("DELETE FROM observations WHERE project LIKE 'bench-reveried-%'").rowcount
n2 = db.execute("DELETE FROM sessions  WHERE project LIKE 'bench-reveried-%'").rowcount
print(f"1. bench: {n1} obs + {n2} sessions")

# 2. Hard-delete soft-deleted obs
n3 = db.execute("DELETE FROM observations WHERE deleted_at IS NOT NULL").rowcount
print(f"2. soft-deleted removed: {n3}")

# 3. Prune empty sessions (no obs AND no prompts)
n4 = db.execute("""DELETE FROM sessions WHERE id NOT IN (SELECT DISTINCT session_id FROM observations WHERE session_id IS NOT NULL)
                   AND id NOT IN (SELECT DISTINCT session_id FROM user_prompts WHERE session_id IS NOT NULL)""").rowcount
print(f"3. empty sessions pruned: {n4}")

# 4. Fix broken supersession
n5 = db.execute("""UPDATE observations SET supersedes = NULL
                   WHERE supersedes IS NOT NULL AND supersedes NOT IN
                         (SELECT sync_id FROM observations WHERE sync_id IS NOT NULL)""").rowcount
print(f"4. broken supersedes fixed: {n5}")

# 5. Backfill empty type
n6 = db.execute("UPDATE observations SET type='manual' WHERE type IS NULL OR type=''").rowcount
print(f"5. empty type backfilled: {n6}")

db.commit()
print(f"POST: obs={cnt('SELECT COUNT(*) FROM observations')} sessions={cnt('SELECT COUNT(*) FROM sessions')}")
db.isolation_level = None
db.execute("VACUUM")
db.close()
print(f"DB size: {os.path.getsize(os.path.expanduser('~/.engram/engram.db'))/1024/1024:.1f} MB")
PY
```

4. **Restart daemon + health check**:
   ```bash
   systemctl --user start reveried
   sleep 3 && curl -sf http://127.0.0.1:7437/health | jq
   ```

## Rollback

```bash
systemctl --user stop reveried
cp ~/.engram/engram.db.bak-<ts> ~/.engram/engram.db
systemctl --user start reveried
```

## Do NOT

- Skip the backup.
- Run while reveried is up (SQLite write-lock contention).
