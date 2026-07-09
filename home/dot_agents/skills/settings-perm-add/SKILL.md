---
name: settings-perm-add
description: Append one or more `Bash(pattern)` permission entries to `~/.claude/settings.json` under `permissions.allow`. Use when the user says "stop asking permission for X", "allow Bash(Y) in settings", "add a Bash perm", or after Claude Code has just prompted to approve a command the user wants permanently allowed. Args — one or more positional patterns (e.g. `"Bash(sleep *)" "Bash(timeout *)"`), plus optional `--dry-run` and `--no-dedupe`.
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
2. **Shadowed by wildcard** — there's an existing `Bash(prefix *)` such that `X` starts with `prefix `. E.g. `Bash(git push foo)` is shadowed by `Bash(git *)`. Skip and report `shadowed by Bash(<wildcard>)`.
3. **Shadowed by absolute-path wildcard** — same as above but with a leading `~/.local/bin/` or `/usr/bin/` prefix. E.g. `Bash(~/.local/bin/cargo build)` is shadowed by `Bash(~/.local/bin/cargo *)`.

Extract existing `Bash(...)` entries with:

```bash
jq -r '.permissions.allow[] | select(startswith("Bash("))' "$SETTINGS"
```

After the pass, if every requested entry is shadowed, exit early with the report — no lock needed, no writes needed.

### 4. Edit settings.json

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
     # Do NOT auto-restore; let the user inspect.
     exit 1
   }
   ```


### 5. Report

Print a summary with:

- **Added**: list of `Bash(...)` entries actually appended
- **Skipped (already present)**: list with reason `exact duplicate`
- **Skipped (shadowed)**: list with the shadowing wildcard
- **File size**: before -> after (line count delta)

If `--dry-run`, the report shows the proposed diff, but no files were touched.

## Safety invariants

- **Always Read before Write/Edit.** Mandatory by the tool contract and protects against mid-edit races.
- **Always re-validate JSON after editing.** A broken `settings.json` bricks every future Claude session.
- **Pure append.** v0 never removes entries. If the user wants removal, tell them to do it by hand or wait for `--remove`.
- **Bash-only.** Reject non-`Bash(...)` patterns at parse time.

## Edge cases handled

- **Shadowing by existing wildcards** — `Bash(git push foo)` is silently dropped if `Bash(git *)` already exists; reported, not added.
- **Exact duplicates** — same string already present; reported as `already present`, not appended twice.
- **Mid-edit JSON corruption** — re-validates with `jq` after Edit; aborts loudly without auto-rollback so the user can inspect.
- **All entries shadowed** — exits before writing; zero side effects.

## Future extensions

- `--remove <pattern>` — exact-match removal.
- `--type Read|Edit|WebFetch|...` — extend beyond `Bash(...)` shape.
- `--prune-shadowed` — proactively remove existing entries that are shadowed by a broader new wildcard (e.g. when adding `Bash(cargo *)`, drop the 12 existing `Bash(cargo build)`/`Bash(cargo test)` literals).
- `--ask-list` and `--deny-list` — write to `permissions.ask` / `permissions.deny` instead of `allow`.
- **Audit mode** — scan the existing allowlist for already-shadowed dead entries (the file currently has ~30 dead RTK literal-rewrite entries) and offer to prune them in one batch.
