---
name: settings-perm-add
description: Append one or more `Bash(pattern)` permission entries to `~/.claude/settings.json` under `permissions.allow`, holding the coord `claude-config` lock for the duration and stealing the lock in-place if it's held by a dead session. Use when the user says "stop asking permission for X", "allow Bash(Y) in settings", "add a Bash perm", or after Claude Code has just prompted to approve a command the user wants permanently allowed. Args — one or more positional patterns (e.g. `"Bash(sleep *)" "Bash(timeout *)"`), plus optional `--dry-run` and `--no-dedupe`.
---

# settings-perm-add — safe Bash permission appender

Append `Bash(...)` allow entries to `~/.claude/settings.json` without races, without duplicates, and without ever leaving the file in a broken state. Designed for the common case where Claude just got blocked on a command, the user says "allow that", and you need to extend the allowlist for every future session.

## When to use

- User says "allow `Bash(foo *)`", "add a permission for X", "stop asking about Y", "whitelist Z"
- Claude Code just prompted for approval of a Bash command and the user wants it permanent
- You're adding a small set (1-10) of new entries — for bulk migrations, edit by hand
- The new entries are all `Bash(...)` shape

**Don't** use this when:

- The permission is for `Read(...)`, `Edit(...)`, `WebFetch(...)`, `mcp__*`, etc. — different shape, out of scope for v0
- The `claude-config` coord lock is held by a **live** peer session — abort and tell the user to coordinate
- The user wants to **remove** an entry — v0 is append-only
- The user wants to edit a non-`allow` block (e.g. `deny`, `ask`) — out of scope for v0
- Bulk-rewriting more than ~10 entries — open the file in an editor

## Procedure

### 1. Parse args

- Positional args: one or more permission patterns. Each must look like `Bash(...)`.
- `--dry-run`: print the diff and the would-be lock acquisition, but do not write or lock.
- `--no-dedupe`: skip the shadowing check (rare; only use when adding a literal that's known to differ from a wildcard).
- Reject any positional that doesn't match `^Bash\(.+\)$` with a clear error.

### 2. Read current settings

```bash
SETTINGS=~/.claude/settings.json
```

Use the **Read** tool on `$SETTINGS` (mandatory before any Edit/Write). Cache the contents in memory — you'll need them for the dedupe pass and for the diff report.

Validate it parses as JSON before touching anything:

```bash
jq -e . "$SETTINGS" >/dev/null || { echo "settings.json is not valid JSON; aborting"; exit 1; }
```

### 3. Shadowing / dedupe pass (unless `--no-dedupe`)

For each requested entry `Bash(X)`:

1. **Exact duplicate** — already present verbatim. Skip and report `already present`.
2. **Shadowed by wildcard** — there's an existing `Bash(prefix *)` such that `X` starts with `prefix `. E.g. `Bash(coord send foo)` is shadowed by `Bash(coord *)`. Skip and report `shadowed by Bash(<wildcard>)`.
3. **Shadowed by absolute-path wildcard** — same as above but with a leading `~/.claude/bin/` or `/usr/bin/` prefix. E.g. `Bash(coord lock x)` is shadowed by `Bash(~/.claude/bin/coord *)`.
4. **New** — not covered. Add to the to-write list.

Extract existing `Bash(...)` entries with:

```bash
jq -r '.permissions.allow[] | select(startswith("Bash("))' "$SETTINGS"
```

After the pass, if every requested entry is shadowed, exit early with the report — no lock needed, no writes needed.

### 4. Acquire the `claude-config` lock

Per `~/.claude/CLAUDE.md`, any write to `~/.claude/*` requires this lock.

```bash
SUMMARY=$(printf '%s, ' "${TO_ADD[@]}" | sed 's/, $//' | head -c 80)
~/.claude/bin/coord lock claude-config \
  --reason "settings-perm-add: $SUMMARY" \
  --ttl 300
```

If acquisition succeeds, jump to step 6.

### 5. Orphan-lock recovery (only if step 4 fails)

The `claude-config` lock is the chicken-and-egg case: this skill is what would normally **add** a permission like `Bash(rm -rf /tmp/claude-coord/locks/*)`, so on first run that permission probably isn't in the allowlist yet. We can't shell-rm the lock directory. Instead, we steal in-place.

1. Read the orphan record:

   ```bash
   LOCKDIR=/tmp/claude-coord/locks/claude-config
   ```

   Use the **Read** tool on `$LOCKDIR/record.json` and `$LOCKDIR/owner` (Read is mandatory before any Write). Cache both contents.

2. Extract `owner_pid` from `record.json`:

   ```bash
   OWNER_PID=$(jq -r .owner_pid "$LOCKDIR/record.json")
   ```

3. Liveness check:

   ```bash
   if kill -0 "$OWNER_PID" 2>/dev/null; then
     echo "ABORT — claude-config lock held by LIVE pid $OWNER_PID; coordinate with that session"
     exit 1
   fi
   ```

   **Never steal a live lock.** If the owner is alive, abort with a clear message and tell the user which pid holds it.

4. The owner is dead — perform an in-place steal. Build new `record.json` with:

   - `owner_session_id`: current session id (read from `$CLAUDE_SESSION_ID` env or `coord whoami`)
   - `owner_pid`: `$$` (current shell pid)
   - `acquired_at`: now (ISO-8601 UTC)
   - `expires_at`: now + 600s
   - `reason`: `"orphan steal from dead pid <old_pid> (settings-perm-add)"`
   - Preserve any other fields from the original record verbatim

5. **Write** (not Edit) the new files using the Write tool — Edit would refuse because the entire content is being replaced:

   ```
   Write $LOCKDIR/record.json   <new JSON>
   Write $LOCKDIR/owner         <current session id>
   ```

6. Verify the steal stuck:

   ```bash
   ~/.claude/bin/coord status claude-config
   ```

   Should show the current session as owner.

### 6. Edit settings.json

Use the **Edit** tool, **never Write**. The file is ~400 lines and rewriting it with Write is wasteful and risky.

1. Identify the last entry of `permissions.allow` — the line right before the closing `]` of the `allow` array. With `jq` this is fragile because jq doesn't preserve formatting; instead, find the textual anchor:

   ```bash
   grep -n '"permissions"' "$SETTINGS"
   ```

   then locate the matching `allow` array's closing `]`. The last entry will be a line like `      "Bash(...)"` (6-space indent, no trailing comma).

2. Edit pattern: replace the last existing entry's line with itself + `,` + the new entries, e.g.:

   - **old_string**:
     ```
           "Bash(last existing entry)"
         ]
     ```
   - **new_string**:
     ```
           "Bash(last existing entry)",
           "Bash(new entry 1)",
           "Bash(new entry 2)"
         ]
     ```

   This preserves the closing `]` and matches the file's existing 6-space indentation.

3. Match the indentation **exactly**. If the file uses 6 spaces, use 6 spaces. If it switches to tabs (it shouldn't), match tabs.

4. After the Edit, re-validate:

   ```bash
   jq -e . "$SETTINGS" >/dev/null || {
     echo "POST-EDIT FAIL — settings.json no longer parses; manual recovery required"
     # Do NOT auto-restore; let the user inspect. The lock will be released in step 7.
     exit 1
   }
   ```

### 7. Release the lock

```bash
~/.claude/bin/coord unlock claude-config
```

Always release, even on failure paths after the lock was acquired. Wrap the edit in a trap if writing this in shell:

```bash
trap '~/.claude/bin/coord unlock claude-config 2>/dev/null || true' EXIT
```

### 8. Report

Print a summary with:

- **Added**: list of `Bash(...)` entries actually appended
- **Skipped (already present)**: list with reason `exact duplicate`
- **Skipped (shadowed)**: list with the shadowing wildcard
- **Lock**: acquired-at, released-at, whether an orphan steal happened, dead pid if so
- **Session**: current session id
- **File size**: before -> after (line count delta)

If `--dry-run`, the report shows the proposed diff and the lock acquisition that would have happened, but no files were touched.

## Safety invariants

- **Never `rm -rf` the lock directory.** Even if/when that permission lands in the allowlist, in-place Read+Write is safer and survives the bootstrap case.
- **Never edit `settings.json` without holding `claude-config`.** Other Claude sessions also write here.
- **Never steal a live lock.** `kill -0 $OWNER_PID` must fail (process gone) before stealing.
- **Always Read before Write/Edit.** Mandatory by the tool contract and protects against mid-edit races.
- **Always re-validate JSON after editing.** A broken `settings.json` bricks every future Claude session.
- **Pure append.** v0 never removes entries. If the user wants removal, tell them to do it by hand or wait for `--remove`.
- **Bash-only.** Reject non-`Bash(...)` patterns at parse time.
- **Never shell-print secret env vars** while building the lock record (per global CLAUDE.md). The session id is fine; do not interpolate `$ANTHROPIC_API_KEY` etc.

## Edge cases handled

- **Orphan lock from a crashed session** — stolen in place via Read+Write of `record.json` and `owner`. No shell `rm` needed.
- **Bootstrap chicken-and-egg** — the skill works even when the allow list does not yet contain `Bash(rm -rf /tmp/claude-coord/locks/*)`, because it never tries to rm.
- **Shadowing by existing wildcards** — `Bash(coord send foo)` is silently dropped if `Bash(coord *)` already exists; reported, not added.
- **Exact duplicates** — same string already present; reported as `already present`, not appended twice.
- **Mid-edit JSON corruption** — re-validates with `jq` after Edit; aborts loudly without auto-rollback so the user can inspect.
- **All entries shadowed** — exits before acquiring the lock; zero side effects.

## Future extensions

- `--remove <pattern>` — exact-match removal, also gated by `claude-config` lock.
- `--type Read|Edit|WebFetch|...` — extend beyond `Bash(...)` shape.
- `--prune-shadowed` — proactively remove existing entries that are shadowed by a broader new wildcard (e.g. when adding `Bash(cargo *)`, drop the 12 existing `Bash(cargo build)`/`Bash(cargo test)` literals).
- `--ask-list` and `--deny-list` — write to `permissions.ask` / `permissions.deny` instead of `allow`.
- **Audit mode** — scan the existing allowlist for already-shadowed dead entries (the file currently has ~30 dead RTK literal-rewrite entries) and offer to prune them in one batch.
