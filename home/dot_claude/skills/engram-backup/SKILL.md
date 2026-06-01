---
name: engram-backup
description: >
  Take a timestamped backup of the engram DB via SQLite's C-level backup API
  (live-consistent, no daemon stop required). Wraps the `engram backup`
  subcommand (driven by the `engram-backup.service` unit). Use when the user
  says "back up engram", "snapshot memory", "before the cleanup", or before
  any risky DB op.
allowed-tools:
  - Bash
tags: [engram, memory, backup, snapshot]
---

# Engram backup

Live-consistent backup using SQLite's online backup API. Runs while reveried
is up — no downtime.

## Usage

Manual one-shot (uses the same code path as the systemd timer):

```bash
~/.local/bin/engram backup
```

Output path: `~/.engram/engram.db.<ISO8601-Z>.bak` (e.g.
`~/.engram/engram.db.20260420T141309Z.bak`). Written beside the live DB, not
into a subdirectory.

## Automatic schedule

- `engram-backup.timer` (systemd --user) runs every 6h
- Fires `engram-backup.service` → `~/.local/bin/engram backup`
- Confirm status: `systemctl --user list-timers engram-backup.timer`

The live-backup API means a snapshot can always be taken — no need to stop
reveried.

## Verify

```bash
ls -lht ~/.engram/engram.db.*.bak | head -5
# Most recent should be < 6h old if the timer is healthy.
```

Integrity check of the latest snapshot:
```bash
LATEST=$(ls -t ~/.engram/engram.db.*.bak | head -1)
python3 -c "import sqlite3; db=sqlite3.connect('$LATEST'); print(db.execute('PRAGMA integrity_check').fetchone())"
# Expected: ('ok',)
```

## Rollback from backup

```bash
systemctl --user stop reveried
cp ~/.engram/engram.db.<ts>.bak ~/.engram/engram.db
systemctl --user start reveried
```

See also `/engram-restore` for a safer restore flow that keeps a pre-restore
safety copy.
