---
name: mcp-wsl-bridge
description: Generate a Windows Claude Desktop `mcpServers` config from the WSL `~/.claude/mcp/` server definitions, wrapping commands with `wsl.exe -d <distro> --` and rewriting WSL paths. Use when the user says "set up MCP on Windows", "bridge my WSL MCP servers to Windows", "claude desktop config from WSL", "wsl mcp bridge". Args — `--source <dir>` default `~/.claude/mcp/`, `--out <path>` default `~/configs/mcp-bridge/claude_desktop_config.json`, `--wsl-distro <name>` default auto-detected, `--include <csv>` / `--exclude <csv>`, `--print` to stdout only.
---

# mcp-wsl-bridge — generate Windows Claude Desktop config from WSL MCP definitions

Reads the WSL-side MCP server definitions and emits a `mcpServers` JSON block suitable for `%APPDATA%\Claude\claude_desktop_config.json` on the Windows host. Each command is wrapped with `wsl.exe -d <distro> --` so the Windows Claude Desktop process can invoke WSL-resident servers. Paths are translated from WSL (`~/`) to absolute Linux paths (`/home/<user>/`). Diffs against an existing output file and writes only changed keys.

## When to use

- User says "set up MCP on Windows", "bridge my WSL MCP servers to Windows", "claude desktop config from WSL", "wsl mcp bridge", "regenerate the Windows MCP config"
- After adding or removing an MCP server in `~/.claude/mcp/` — re-run to sync the Windows config
- After changing WSL distro name or user paths

**Don't** use this when:
- The user wants to edit the in-WSL `settings.json` — use `update-config` or `/settings-perm-add`
- The user wants to add a Windows-native MCP server (not WSL-backed) — edit `claude_desktop_config.json` manually; this skill only handles WSL bridges
- `wsl.exe` is not available in PATH (non-WSL environment) — skill will warn and exit

## Args

```
--source <dir>           optional  directory of MCP server JSON configs
                                   (default: ~/.claude/mcp/)
--out <path>             optional  output file path
                                   (default: ~/configs/mcp-bridge/claude_desktop_config.json)
--wsl-distro <name>      optional  WSL distro name (default: auto-detect via `wsl.exe -l -v`,
                                   fallback: Ubuntu)
--include <csv>          optional  only include these server names
--exclude <csv>          optional  skip these server names
--print                  optional  print to stdout instead of writing to --out
```

## Procedure

### 1. Detect environment

- Verify `wsl.exe` is accessible (only needed for validation; generation works anywhere).
- If `--wsl-distro` is not given, run `wsl.exe -l -v` and pick the `*` (default) distro. Fallback to `Ubuntu` if detection fails or the tool is unavailable. Log the detected distro name.

### 2. Read source MCP definitions

- Glob `<source>/*.json`. Each file is one server definition with at least `{ "command": "...", "args": [...], "env": {...} }`.
- If `--include` given, filter to those names (filename without `.json` extension).
- If `--exclude` given, remove those names.
- Warn on malformed JSON (skip the file, continue).

### 3. Transform each server config

For each server definition:

**Command wrapping:**
```
original:   { "command": "/home/ctodie/.local/bin/engram", "args": ["serve"] }
wrapped:    { "command": "wsl.exe", "args": ["-d", "<distro>", "--", "/home/ctodie/.local/bin/engram", "serve"] }
```

**Path translation** (applied to `command`, `args`, and `env` values):
- `~/foo` → `/home/<user>/foo`
- `/home/ctodie/...` → keep as-is (already absolute)
- Windows-style paths (e.g. `C:\...`) in `args` or `env` → emit a warning and leave unchanged (Windows paths in WSL args are a user concern)
- `$HOME` → `/home/<user>` (expand known vars at generation time)

**Env-var secrets:** any key matching `*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*` — replace value with `"REPLACE_ME_<KEY_NAME>"` and emit a one-line warning listing which vars were masked. Never echo secret values.

### 4. Build the output JSON

```json
{
  "mcpServers": {
    "engram": {
      "command": "wsl.exe",
      "args": ["-d", "Ubuntu", "--", "/home/ctodie/.local/bin/engram", "serve"],
      "env": { ... }
    },
    ...
  }
}
```

### 5. Diff and write

- If `--print`, write to stdout and exit.
- If `--out` file exists, parse it and diff at the `mcpServers.<name>` level. Print a summary of changed/added/removed keys.
- Write the merged result (existing unchanged keys + new/updated keys). Never silently delete a server that was in the old file but absent from the new scan — warn instead and require `--exclude <name>` to confirm removal.

### 6. Post-write notice

```
mcp-wsl-bridge: wrote <N> server(s) to ~/configs/mcp-bridge/claude_desktop_config.json
  added:   gdrive
  updated: engram (command changed)
  unchanged: linear, gcal, gmail

Copy this file to %APPDATA%\Claude\claude_desktop_config.json on the Windows host,
then restart Claude Desktop.
```

## Existing template

`~/configs/mcp-bridge/wsl-reverse-bridge-template.json` contains a manually curated baseline. This skill auto-regenerates that file when MCP servers are added/removed. If the template exists, load it as the "existing" file for the diff step (step 5).

## Security notes

- Never echo or log secret-named env var values (enforced in step 3).
- The generated config will be copied to a Windows path — warn the user if any non-masked env var contains a path that looks like a secret (`/.*\.key`, `/.*\.pem`, etc.).
