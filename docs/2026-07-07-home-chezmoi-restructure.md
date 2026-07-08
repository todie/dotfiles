<!-- lineage
role: change-record
conforms_to: ../CLAUDE.md
consumes: docs/chezmoi-migration.md (original migration), docs/tooling-strategy.md
-->

# 2026-07-07 — home directory + chezmoi best-in-class restructure

Operator-approved plan (interviewed decisions: reclaim everything incl. model
audit · moderate XDG depth · all four chezmoi upgrades · skills unified under
chezmoi). Commits: `6c7dc73` (reconcile) · `31a5385` (adoption) · `9ca1fb5`
(symlink fix) · `9e27b83` (xdg) · this record.

## What changed

- **Drift reconciled live→repo** after ~4 weeks (live was newer everywhere
  except one bidirectional file; `loop-discipline.md` kept live hook naming —
  the source-side `guard-main-push.sh` rename is PARKED, decide separately).
- **Coverage**: `.gitconfig` (templated — identity from `.chezmoidata.toml`,
  gh credential helper on the mise SHIM not a version path), `.ssh/config`,
  `gh/config.yml` (`hosts.yml` fenced — OAuth tokens). Global gitignore
  consolidated to XDG `git/ignore`; `~/.gitignore_global` retired.
- **`.chezmoidata.toml` + de-hardcoding**: no `/home/ctodie` literals left in
  zshrc/mcp sources (`$HOME` in shell, `{{ .chezmoi.homeDir }}` in templates).
- **`.chezmoiexternal.toml.tmpl`**: kubecolor 0.6.0 pinned + per-arch sha256;
  k8s-tools run_once is shim-generation only; tests target the external.
  zsh plugins deliberately NOT externalized (plugins.zsh self-heal owns them).
- **`.chezmoiversion`** floor 2.70.4 (in `home/`, the effective root).
- **age fallback**: `encryption = "age"` (top-level key — after a `[table]`
  header TOML scopes it wrong); op-token bootstrap file now an encrypted
  source. Fresh machine chain: age key → decrypt bootstrap → 1P renders rest.
- **Skills single-authority**: `home/dot_agents/skills/` (37) deploys real
  files to `~/.agents/skills`; symlink layer retired. EXCEPTION: cross-repo
  skills (agentic `packages/skills/`) stay live symlinks — chezmoi
  DEREFERENCES raw source symlinks into stale copies (learned the hard way).
- **XDG moderate**: bun canonical at `~/.cache/.bun` (stale `~/.bun` 1.3.11
  deleted), nvm retired, npm cache → XDG, LESSHISTFILE/NODE_REPL_HISTORY
  fixed, Pilot PATH dup removed.
- **Reclaim**: ~123G caches (hf hub, sccache, npm, go, pip). uv cache SKIPPED
  — live voicemode services hold its lock. Models: operator chose to keep all.
- **~ decluttered**: 21 docs → `~/docs/{notes,reference}/`, 16 junk/backup
  items removed. `~/.zshrc-ctodie` is a REAL machine-local override file
  (sourced by .zshrc), not a backup — never sweep it.

## Rejected (churn > value — do not re-propose without new evidence)

CARGO_HOME/RUSTUP_HOME/GOPATH/GOROOT/DOCKER_CONFIG/IPYTHONDIR/JUPYTER
relocations; Chrome profile move (hardcoded `~/.config/google-chrome`);
zsh-plugin externals (dual-ownership with plugins.zsh).

## Outstanding (operator)

1. Run the hook re-add block (8 files, guard-fenced from agents), then commit.
2. Back up `~/.config/chezmoi/key.txt` (age identity) to 1Password — the
   encrypted bootstrap is unrecoverable without it.
3. Secret-adjacent review list (agent never touched): `.secrets.bak-pre-rw-switch`,
   `.secrets.bak.1780124854`, `todie-admin-dwd.txt`, `.s3cfg`,
   `.config/{ollama-auth-proxy,pilot}.env` — review, rotate, delete by hand.
4. Push (5 commits local-only on main).
