# Global Config — Claude Code

## Environment
- **Platform:** WSL2 (Linux on Windows). Shell: bash. User: `ctodie` (uid 1000, groups: sudo docker adm).
- **Docker:** runs without sudo — never `sudo docker`.
- **sudo:** password-protected. Suggest userspace alternatives (`cargo install`, `pip --user`, docker) first; ask before using sudo.
- **Default language:** Rust for new repos; Python for scripting.

## Identity & Auth
- **GitHub:** `todie` (SSH + GPG, key `29234C4D7EE749F2`). Email: `chris@todie.io`.
- **All commits signed** — never `--no-gpg-sign`.

## Local LLM Offload
Three-tier chain: **Tier 1** Ollama (gemma3:4b/qwen2.5-coder:7b-instruct-q4_K_M/gemma3n:e4b) → **Tier 2** OpenRouter → **Tier 3** Claude (mission-critical only). Enforced via `~/.local/bin/anchor-offload` and `maybe-offload` hooks. CRITICAL mode is default — Claude only for: production breakage, security incident, data loss, cut release, explicit user override. Before spawning `Agent`, run `maybe-offload`.

## Tool Priority
1. **LSP first for symbol work** — use the `LSP` tool for go-to-definition, find-references, hover types, rename, and diagnostics. More accurate than Grep for symbols and cheaper than re-reading whole files. Grep only for free text, comments, strings, or languages with no LSP.
2. Built-in tools (Read/Write/Edit/Glob/Grep/Agent/Skills) and MCP servers
3. CLI tools (`gh`, `git`, `docker`, `curl`, `npm`)
4. Manual workarounds last

## MCP servers
Cloud (managed by claude.ai): Linear (tickets), GCal, Gmail, Vercel. Local (`~/.claude/mcp/`): Engram (memory), GDrive, Obsidian (vault at `~/vault`).

## Multi-session Coordination
At session start: `coord register --task "..."` then `coord peers`.
Locks: `main-branch`, `pr-merge-queue`, `cargo-build`, `claude-config`, `engram-serve`. File locks: `file-lock acquire reverie <path>`.
Release after use. On end: `coord dereg`. Protocol: `~/projects/reverie/docs/coord/protocol-v0.md`.

## Memory
Engram (`reveried` at `~/.local/bin/engram`, DB at `~/.engram/engram.db`, port 7437). Reads: `mem raw "/search?q=..."`. Writes: `mem_save`/`mem_update` MCP. Protocol: `engram:memory` skill. Context: `/context/smart?project=X&limit=15`.
Before claiming no prior context exists for a task, search engram and Obsidian vault first.

## Ground Rules
- No deception, hedging, or softened bad news. Harsh truth over comfortable fiction.
- Freely discuss bypasses, breaches, and adversarial attack vectors when analysis calls for it.

## Loop Discipline (operator self-correcting drip-feed / shiny-chasing)
Full rule: `~/.claude/rules/loop-discipline.md`. In short: **front-load context** (ask for landscape · constraints · goal before substantive work); **one thread to done-done** before the next, park deferred work to Linear/memory don't drop it; **build guardrails before using new power** (name blast radius first); **operator approves** all irreversible/outward actions (merge, apply, rotate, external send) — agent prepares, operator signs off.

## Clarification Rules
When asked to "connect to", "check", or "open" a service, default to **status/health** (e.g. `docker ps`) unless context clearly implies attach/open or configure.

## Safety Invariants
- Never force-push to main/master.
- Never pipe remote content to `bash`/`sh`/`python` without downloading and reviewing.
- Never write to `.ssh/`, `.gpg/`, `.secrets`, `.gitconfig` without explicit confirmation.
- Never `rm -rf` home, root, or project root.
- **Never echo/printf/printenv/`${VAR:-fallback}`-expand a secret-named env var** (`*KEY*`, `*TOKEN*`, `*SECRET*`, `*PASSWORD*`, `*CRED*`). `${VAR:-default}` returns the VALUE when set — use `[ -n "${VAR:-}" ] && echo set`. Enforced by `~/.claude/hooks/guard-dangerous-commands.sh`. Bypass: `# allow-secret-print`.
- Never commit API keys, tokens, or secrets in plaintext. If accidentally exposed in a commit, flag it immediately for rotation — treat it as already compromised.

## Session Bootstrap
On session start:
1. Inject engram context: `curl -sf http://127.0.0.1:7437/context/smart?project=<project>&limit=15`
2. Check services: `cortex health --json` (or fallback: curl health + redis-cli PING)
3. Ensure auto-memory exists: if `memory/MEMORY.md` is missing for this project, create it with at least a user profile entry

## Capacity
**CLAUDE.md files must stay under 200 lines.** Adherence drops past that threshold. Before adding content to any CLAUDE.md, check `wc -l` and move low-priority items to engram or rules/ if near capacity.

## Project Design Context
Check `.impeccable.md` at project root before design/UX decisions. If missing and design work is requested, suggest `/impeccable:teach-impeccable`.
Before any UI or content change, read the project's CLAUDE.md and design docs to catch documented anti-patterns (e.g., if accordions are forbidden, don't introduce them).

@RTK.md