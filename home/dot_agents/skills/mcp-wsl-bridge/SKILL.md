---
name: mcp-wsl-bridge
description: Generate a Windows Claude Desktop `claude_desktop_config.json` (and a parallel Claude Code CLI MCP file) from the stdio MCP server configs in `~/.claude/mcp/*.json`. Each WSL command is wrapped as `wsl.exe -d <distro> -- bash -lc 'exec …'`, paths are translated from `~` to `/home/ctodie`, and secret-named env vars are replaced with placeholders + a warning. Use when the user says "set up MCP on Windows", "bridge my WSL MCP servers", "regenerate claude_desktop_config", or after adding/removing a server in `~/.claude/mcp/`. Args — `--source <dir>` (default `~/.claude/mcp/`), `--out <path>` (default `~/configs/mcp-bridge/claude_desktop_config.json`), `--wsl-distro <name>` (default auto-detect via `wsl.exe -l -v` or `Ubuntu`), `--include <csv>`, `--exclude <csv>`, `--print` (stdout instead of write), `--dry-run`.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
tags: [mcp, wsl, windows, bridge, config]
---

# mcp-wsl-bridge — generate Windows Claude config from WSL MCP defs

Single source of truth lives in WSL at `~/.claude/mcp/<server>.json` — one JSON file per stdio MCP server, with `command` / `args` / `env`. This skill reads those, wraps each one for `wsl.exe`, and emits a Windows-shaped `claude_desktop_config.json` (and optionally a Claude Code CLI `.mcp.json`) so the same servers are reachable from Windows-side Claude Desktop or Claude Code.

Reference implementation already on disk at `~/configs/mcp-bridge/claude_desktop_config.json` and `~/configs/mcp-bridge/README.md` — this skill is the regenerator. When a server is added to or removed from `~/.claude/mcp/`, run this skill to keep the Windows side in sync without hand-editing.

## When to use

- User says "set up MCP on Windows", "bridge my WSL MCP servers", "regenerate the claude desktop config", "wsl mcp bridge"
- After adding or removing a `~/.claude/mcp/<server>.json`
- After changing the WSL distro name (e.g. `Ubuntu` → `Ubuntu-22.04`) and the existing config needs every entry updated

**Don't** use this when:
- The user wants to edit the in-WSL `~/.claude/settings.json` — that's `/update-config`, not this. This skill only writes Windows-targeted files.
- The user wants to bridge a Windows-side MCP *to* WSL — that's the reverse direction; this skill writes the forward direction only. The template for reverse lives at `~/configs/mcp-bridge/wsl-reverse-bridge-template.json` and is edited by hand.
- There are no servers under `~/.claude/mcp/` — abort with a clear error rather than emit an empty `mcpServers` block.

## Procedure

### 1. Parse args

- `--source <dir>`: directory of stdio MCP JSON files (default `~/.claude/mcp/`)
- `--out <path>`: destination for the generated config (default `~/configs/mcp-bridge/claude_desktop_config.json`)
- `--wsl-distro <name>`: distro to pass to `wsl.exe -d` (default: auto-detect via `wsl.exe -l -v` — the line starred `*` — falling back to `Ubuntu`)
- `--include <csv>`: only generate entries for these server names (matched against the JSON filename without `.json`)
- `--exclude <csv>`: skip these server names
- `--print`: write to stdout instead of `--out`
- `--dry-run`: print the planned `mcpServers` object + a diff against the existing `--out` file, do NOT write

### 2. Detect distro

If `--wsl-distro` was not passed, run `wsl.exe -l -v` (the output is UTF-16 with embedded NULs — strip them: `wsl.exe -l -v 2>/dev/null | tr -d '\0'`). Parse for the line that starts with `*` (the default distro). Take the second whitespace-separated token. Fall back to `Ubuntu` if the parse fails.

Print: `Distro detected: Ubuntu` so the user can override before the write lands.

### 3. Glob source configs

List `<source>/*.json`. Apply `--include` / `--exclude`. Abort with a clear error if the result set is empty:

```
mcp-wsl-bridge: no MCP configs found under ~/.claude/mcp/ (after include/exclude). Refusing to emit an empty mcpServers block.
```

### 4. Parse each source config

Each file has the stdio MCP shape:

```json
{
  "command": "<binary or shell>",
  "args": ["<arg1>", "<arg2>", "..."],
  "env": { "KEY": "value" }
}
```

Read with the Read tool, parse with `python3 -c 'import json, sys; …'` for safety (do NOT eval, do NOT `jq` with positional surprises).

### 5. Translate paths

For every string value in `command`, `args`, and `env`:

- `~/foo` → `/home/ctodie/foo`
- `$HOME/foo` → `/home/ctodie/foo`
- bare `~` → `/home/ctodie`

Do NOT translate paths inside `env` *values* that look like Windows paths already (`C:\…` or `/mnt/c/…`) — leave those alone, they're either intentional Windows refs or already-translated.

### 6. Sanitize secrets

For each `env` key, if it matches `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*CRED*` (case-insensitive), replace the value with the literal string `"<REPLACE_ME_SECRET>"` and emit a warning line:

```
WARN: server=<name> env=<KEY> — secret value replaced with placeholder. Edit ~/configs/mcp-bridge/claude_desktop_config.json before deploying.
```

Never echo the original secret to stdout, even truncated. This is enforced by the global `guard-dangerous-commands` hook anyway — but the skill must not try to bypass it.

Sourced-from-file secrets (`. $HOME/.secrets && set +a && exec …` patterns, as in the 1Password config) are *not* secrets in the JSON itself — leave the sourcing command intact. The actual `.secrets` file stays in WSL and is read at runtime by the `bash -lc` shell.

### 7. Build the `wsl.exe` wrapper

For each parsed source server, build the Windows-side entry:

```json
{
  "command": "wsl.exe",
  "args": [
    "-d", "<distro>",
    "--cd", "<home-dir-if-needed>",   // optional, only for engram (needs CWD for relative paths)
    "--",
    "bash", "-lc",
    "<env-prefix> exec <command> <args...>"
  ]
}
```

**`bash -lc` is mandatory** (login shell, picks up `~/.profile`, `~/.bashrc`, `~/.local/bin`, nvm/asdf shims). Plain `bash -c` fails to find `engram`, `obsidian-mcp`, `op-mcp`, etc.

**`exec` is mandatory** as the final invocation — ensures SIGHUP from Claude's stdin-close reaches the MCP binary rather than the wrapping shell. Without `exec`, processes leak when the Windows-side session ends.

**Env prefix:** join non-secret env vars as `KEY1=val1 KEY2=val2`. If the source config sourced from `$HOME/.secrets`, preserve that as a leading `set -a && . $HOME/.secrets && set +a && …` block in the bash invocation.

**`--cd`:** only emit for servers whose source config used relative paths in `command` or `args` (e.g. engram with `mcp --tools=agent` — the binary path is absolute but the daemon may resolve relative DB paths from CWD). When in doubt, prefer absolute paths and skip `--cd`.

### 8. Emit the JSON

Build the final shape:

```json
{
  "_comment": "Generated by mcp-wsl-bridge on <ISO date> from ~/.claude/mcp/. Edit the source files, not this — re-run the skill to regenerate.",
  "mcpServers": {
    "engram":   { "command": "wsl.exe", "args": ["..."] },
    "obsidian": { "command": "wsl.exe", "args": ["..."] },
    ...
  }
}
```

Pretty-print with 2-space indent. Use `python3 -c 'import json, sys; json.dump(obj, sys.stdout, indent=2)'` — do not hand-roll the JSON writer.

### 9. Diff against existing `--out`

If `--out` already exists:

1. Read it.
2. Parse its `mcpServers` block.
3. Compute the set of server names in old vs new.
4. For each server present in both, diff the `args` array (the only field likely to change).
5. Print a one-line summary per server: `engram: unchanged`, `obsidian: args changed`, `new-server: added`, `removed-server: removed`.

If `--dry-run`, stop here. Do not write.

### 10. Write

If not `--dry-run` and not `--print`:

- Write the full file to `--out` (overwrite — this is a generator, not a merger).
- If `--print`, dump to stdout instead.

Always print the final destination path so the user knows where it landed:

```
Wrote /home/ctodie/configs/mcp-bridge/claude_desktop_config.json (4 servers, 0 secrets replaced)
```

### 11. Report

Print:

- Number of servers emitted
- Number of secrets replaced with placeholders
- Diff summary (servers added / removed / changed since last run)
- One-line reminder: `Deploy: copy to C:\Users\chris\AppData\Roaming\Claude\claude_desktop_config.json`

## Safety invariants

- **Never** echo a secret value, even truncated, even in a "preview" or "diff" line. Replace with placeholder and warn.
- **Never** emit an empty `mcpServers` block — abort if the source dir is empty.
- **Never** strip the `bash -lc` wrapper or the `exec` prefix — they are correctness requirements, not optimization targets.
- **Never** translate Windows-shaped paths in env values (`C:\…`, `/mnt/c/…`). They're already correct or intentional.
- **Always** detect the distro fresh on each run — the user may have renamed it (`Ubuntu` → `Ubuntu-22.04`) and the existing config will silently break.
- **Always** print the destination path on write so the user knows where to find the output.
- **Always** include the `_comment` field at the top of the generated JSON so anyone reading the file knows it's generator-output, not hand-edited.

## Example invocation

Dry-run against the current source dir, with diff against the existing output:

```
mcp-wsl-bridge --dry-run
```

Expected output shape:

```
Distro detected: Ubuntu
Source: /home/ctodie/.claude/mcp/ (4 files)

Planned mcpServers:
  engram        wsl.exe -d Ubuntu -- bash -lc 'exec /home/ctodie/.local/bin/engram mcp --tools=agent'
  obsidian      wsl.exe -d Ubuntu -- bash -lc 'exec obsidian-mcp /home/ctodie/vault'
  google-drive  wsl.exe -d Ubuntu -- bash -lc 'GOOGLE_DRIVE_OAUTH_CREDENTIALS=/home/ctodie/.config/google-drive-mcp/gcp-oauth.keys.json exec npx @piotr-agier/google-drive-mcp'
  1password     wsl.exe -d Ubuntu -- bash -lc 'set -a && . $HOME/.secrets && set +a && OP_PATH=/home/ctodie/.local/bin/op exec /home/ctodie/.local/node/bin/op-mcp'

Diff vs existing /home/ctodie/configs/mcp-bridge/claude_desktop_config.json:
  engram:        unchanged
  obsidian:      unchanged
  google-drive:  unchanged
  1password:     unchanged

Dry-run — no file written.
```

Real run that regenerates the file:

```
mcp-wsl-bridge
# → Wrote /home/ctodie/configs/mcp-bridge/claude_desktop_config.json (4 servers, 0 secrets replaced)
# → Deploy: copy to C:\Users\chris\AppData\Roaming\Claude\claude_desktop_config.json
```

Print to stdout for piping into another tool:

```
mcp-wsl-bridge --print | jq '.mcpServers | keys'
```

## Future extensions

- **`--also-claude-code <path>`** to also emit the Windows Claude Code CLI `.mcp.json` (slightly different shape — no top-level `_comment`, otherwise the same servers).
- **`--validate`** to spawn each `wsl.exe …` invocation with `--help` or a known-safe probe and confirm the binary actually exists on the WSL side before declaring success.
- **`--merge`** instead of overwrite — preserve hand-added entries in the destination file that don't have a matching source config. Useful once Claude Desktop's Windows-only MCPs are mixed in.
- **`--reverse-template`** to also regenerate `wsl-reverse-bridge-template.json` from Windows-side `.exe` paths if the user maintains a list of Windows MCPs to bridge into WSL.
- **Auto-detect Windows username** (currently the README hard-codes `chris`) via `wsl.exe -- powershell.exe -Command '$env:USERNAME'` so the deploy hint line is accurate per-machine.
