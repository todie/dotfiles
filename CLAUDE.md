# dotfiles

Personal shell + terminal environment for `todie`, managed with **chezmoi**.
Structured for ongoing iteration.

## Layout

The chezmoi source tree lives under `home/` (`.chezmoiroot` points there), so paths
use chezmoi naming (`dot_`, `private_`, `executable_`, `.tmpl`):

```
home/
  dot_zshrc                          — zsh entry point        (→ ~/.zshrc)
  dot_zshenv                         — non-interactive env     (→ ~/.zshenv)
  dot_config/zsh/lib/*.zsh           — functions, env, options, plugins, completions, aliases, tmux, secrets
  dot_config/zsh/private_secrets.env.tmpl — app keys, rendered from 1Password at apply
  dot_tmux.conf, dot_tmux.conf.d/claude.conf
  dot_local/bin/executable_*         — theme, zedw, tmux-* helpers  (→ ~/.local/bin)
  dot_claude/hooks/executable_*      — Claude Code hooks            (→ ~/.claude/hooks)
  starship/{base.toml,themes/*.toml} — theme palettes (source-input; .chezmoiignore'd, read by `theme`)
  run_once_* / run_onchange_*        — plugin bootstrap, completion gen, theme generation
```

Other top-level: `agents/` (skill defs), `docs/` (design + migration records),
`test/zsh-health.zsh`, `macos/defaults.sh`, `chezmoi.toml` (reference config).

## Adding / changing a dotfile

chezmoi-managed — these are real files, **not** symlinks. Do **not** add an
`install.sh`-style symlink step (the old symlink machinery was retired).

1. `chezmoi add ~/.foo` (ingests with correct naming) — or create `home/dot_foo`.
2. Preview + deploy: `chezmoi diff` → `chezmoi apply`. In-place: `chezmoi edit --apply ~/.foo`.
3. Commit (signed): `feat(<scope>): add <what>`.

## Theming

`theme set <name>` regenerates starship + tmux + fzf from one palette (8 themes;
`theme list` / `theme next`). WSL Windows-Terminal sync is opt-in: `DOTFILES_THEME_WT=1`.

## Secrets

- `~/.secrets` is **operator-managed** (holds `OP_SERVICE_ACCOUNT_TOKEN`); chezmoi
  does not own it (`home/.chezmoiignore`).
- App keys (`ANTHROPIC_API_KEY`, etc.) render from 1Password to
  `~/.config/zsh/secrets.env` at apply via `onepasswordRead` (service mode).

## Plugin policy

Keep the plugin list in `home/dot_config/zsh/lib/plugins.zsh` **minimal** — only
tools used daily. Comment out optional plugins; don't delete them.

## Commit style

Conventional commits, scope = config domain: `feat(zsh): …`, `fix(aliases): …`,
`chore: …`. All commits signed.

## Install (fresh machine)

```bash
chezmoi init --apply todie     # clone repo + apply to ~
```
Requires the 1Password CLI signed in (or `OP_SERVICE_ACCOUNT_TOKEN` set) for secret
rendering. CI (`.github/workflows/ci.yml`) runs shellcheck + `zsh -n` + tmux parse.
