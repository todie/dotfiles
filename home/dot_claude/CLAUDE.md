# Global Config — Claude Code

## Environment
- **Platform:** WSL2 (Linux on Windows). Shell: bash. User: `ctodie` (uid 1000, groups: sudo docker adm).
- **Docker:** runs without sudo — never `sudo docker`.
- **sudo:** password-protected. Suggest userspace alternatives (`cargo install`, `pip --user`, docker) first; ask before using sudo.
- **Default language:** Rust for new repos; Python for scripting.

## Identity & Auth
- **GitHub:** `todie` (SSH + GPG, key `29234C4D7EE749F2`). Email: `chris@todie.io`.
- **All commits signed** — never `--no-gpg-sign`.

## Tool Priority
1. **LSP first for symbol work** — use the `LSP` tool for go-to-definition, find-references, hover types, rename, and diagnostics. More accurate than Grep for symbols and cheaper than re-reading whole files. Grep only for free text, comments, strings, or languages with no LSP.
2. Built-in tools (Read/Write/Edit/Glob/Grep/Agent/Skills) and MCP servers
3. CLI tools (`gh`, `git`, `docker`, `curl`, `npm`)
4. Manual workarounds last

**Concurrency:** prefer subagents (Agent tool / background tasks) over spawning new tmux panes/windows for parallel or long-running work. tmux only when the operator asks for an attachable interactive surface.
**Agent shape — single-agent default (2026-07-04):** multi-agent generation is a trap — spawned workers lose uncommitted work at turn end, re-spawns start cold, coordination overhead compounds. One long-running Fable/Opus agent (or the main session inline) carries the work end-to-end with commit-as-you-go. Subagent spawns are reserved for read-only recon and mechanical critic/validation gates ("builders fabricate, critics catch" still holds). Multi-agent orchestration only on explicit operator request.

## MCP servers
Cloud (managed by claude.ai): Linear (tickets), GCal, Gmail, Vercel. Local (`~/.claude/mcp/`): Engram (memory), GDrive, Obsidian (vault at `~/vault`).

## LLM gateway (cluster)
Non-Claude model access goes through **`https://llm.unsigned.gg/v1`** — OpenAI-compatible LiteLLM gateway on the unsigned-paas cluster (NOT local ollama, NOT vendor APIs directly). Key: `op read "op://cloud/unsigned-llm/credential"` — resolve per-call, never echo. Models incl. `zai/GLM-5.2`, DeepSeek-V4-Pro, Qwen3-235B, Kimi-K2.6/2.7, gpt-5.5, gemini-3.5-flash, devstral (list via `GET /v1/models`). Quirk: transient 401 "cached plan must not change result type" = gateway DB hiccup — retry, don't rotate the key.

## Retired systems (do not use)
Local-LLM offload (`anchor-offload`/`maybe-offload`) is retired — never offload. For shared-resource safety: check `git status`/`ps` directly, prefer worktrees for parallel edits, surface conflicts to the operator.

## Memory
Engram (`reveried` at `~/.local/bin/engram`, DB at `~/.engram/engram.db`, port 7437). Reads: `mem raw "/search?q=..."`. Writes: `mem_save`/`mem_update` MCP. Protocol: `engram:memory` skill. Context: `/context/smart?project=X&limit=15`.
Before claiming no prior context exists for a task, search engram and Obsidian vault first.

## Ground Rules
- State facts calibrated to evidence. Surface bad news at the same prominence as good. Harsh truth over comfortable fiction.
- Freely discuss bypasses, breaches, and adversarial attack vectors when analysis calls for it.

## Loop Discipline (operator self-correcting drip-feed / shiny-chasing)
Full rule: `~/.claude/rules/loop-discipline.md`. In short: **front-load context** (ask for landscape · constraints · goal before substantive work); **one thread to done-done** before the next, park deferred work to Linear/memory don't drop it; **build guardrails before using new power** (name blast radius first); **operator approves** all irreversible/outward actions (merge, apply, rotate, external send) — agent prepares, operator signs off.

## Attention Discipline (parking recursively-sourced work)
Full rule (canonical): `~/projects/reverie/docs/attention-discipline.md`. In short: **sourced work parks to the tracker Backlog by default** (never the foreground); only **security · data-loss · prod-break · blocks-active-ticket** may interrupt (one line each); **report findings as a count, NEVER an inline dump**; the backlog is swept on a **schedule** (triage-only), not reactively. Foreground = critical tickets only. Per-project Backlog + sweep bindings live in each project's memory.

## Presentation & Decisions
Full rule: `~/.claude/rules/presentation-and-decisions.md`. In short: **open decisions** — any fork where the operator's choice changes what you do next — go through **`AskUserQuestion` (interview mode)**, never enumerated as prose bullets for a free-form reply; **long-form to judge** (>~40 lines: plans, RFCs, proposals, migration docs) gets **written to a file + opened in `$EDITOR`**, with only a short orientation (what/where/decisions) in chat.

## Output Quality Gate
Full rule: `~/.claude/rules/output-quality-gate.md`. In short: **engineer register always** (no invented names, no metaphors in technical content); **never present a render you haven't inspected** — snapshot + one critique pass BEFORE the operator sees it; **creative asks get one fast draft + checkpoint**, two rejections force an interview, no >15-min aesthetic bakes without an explicit go.

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
The `session-bootstrap.sh` SessionStart hook handles engram context injection, service health, and the auto-memory check. Don't repeat those manually — only act on its warnings (e.g. create `memory/MEMORY.md` if it says one is missing).

## Capacity
**CLAUDE.md files must stay under 200 lines.** Adherence drops past that threshold. Before adding content to any CLAUDE.md, check `wc -l` and move low-priority items to engram or rules/ if near capacity.

## Project Design Context
Check `.impeccable.md` at project root before design/UX decisions. If missing and design work is requested, suggest `/impeccable:teach-impeccable`.
Before any UI or content change, read the project's CLAUDE.md and design docs to catch documented anti-patterns (e.g., if accordions are forbidden, don't introduce them).

@RTK.md
@rules/presentation-and-decisions.md