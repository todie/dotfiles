---
name: engram-restore
description: >
  Restore the engram DB from a timestamped backup in `~/.engram/`
  (files named `engram.db.<ts>.bak`).
  Stops reveried, atomically swaps the DB file (taking a safety copy of the
  current state first), verifies integrity, and restarts. Use when the user
  says "restore engram", "roll back the db", "revert to backup", or after a
  botched migration / cleanup.
allowed-tools:
  - Bash
tags: [engram, memory, restore, rollback]
---

# Engram restore

Swap the live DB for a backup snapshot. Keeps a pre-restore safety copy so
the restore itself can be rolled back.

## Steps

1. **List backups**:
   ```bash
   ls -lht ~/.engram/engram.db.*.bak
   ```
   Pick the right timestamp (most-recent-pre-incident, not blindly latest).
   Set `BACKUP=~/.engram/engram.db.<ts>.bak` for the steps below.

2. **Stop daemon**:
   ```bash
   systemctl --user stop reveried
   sleep 2 && ! curl -sf http://127.0.0.1:7437/health
   ```

3. **Safety copy of current state**:
   ```bash
   cp ~/.engram/engram.db ~/.engram/engram.db.pre-restore-$(date +%Y%m%d-%H%M%S)
   ```

4. **Verify backup integrity before restoring**:
   ```bash
   python3 -c "import sqlite3; db=sqlite3.connect('$BACKUP'); print(db.execute('PRAGMA integrity_check').fetchone())"
   # Must print ('ok',) — abort if anything else.
   ```

5. **Atomic swap**:
   ```bash
   cp ~/.engram/engram.db.<ts>.bak ~/.engram/engram.db
   ```

6. **Restart + health check**:
   ```bash
   systemctl --user start reveried
   sleep 3 && curl -sf http://127.0.0.1:7437/health | jq
   ```

7. **Post-restore sanity**:
   ```bash
   python3 -c "import sqlite3; db=sqlite3.connect('$HOME/.engram/engram.db'); print(db.execute('SELECT COUNT(*) FROM observations').fetchone()); print(db.execute('SELECT COUNT(*) FROM sessions').fetchone())"
   ```
   Compare counts against what was expected from the backup timestamp.

## Rollback of the restore

If the restored backup itself is bad (corrupt, wrong timestamp, etc):

```bash
systemctl --user stop reveried
cp ~/.engram/engram.db.pre-restore-<ts> ~/.engram/engram.db
systemctl --user start reveried
```

## Do NOT

- Skip the safety copy in step 3 — without it, a bad backup choice is permanent.
- Skip the integrity_check in step 4 — restoring a corrupt backup is worse than no restore.
- Start reveried during the swap — SQLite can end up in inconsistent state.
