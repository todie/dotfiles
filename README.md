# dotfiles

Personal shell + terminal environment for `todie`, managed with [chezmoi](https://chezmoi.io).

## Requirements

- zsh, git
- [chezmoi](https://chezmoi.io)
- 1Password CLI (`op`) signed in, or `OP_SERVICE_ACCOUNT_TOKEN` set — for secret rendering
- optional: [starship](https://starship.rs), [eza](https://github.com/eza-community/eza), bat, fzf, zoxide

## Install

```bash
chezmoi init --apply todie
```

chezmoi clones this repo into its source dir and applies the `home/` tree to `~`
as **real files** (not symlinks), so your live config is decoupled from the repo's
git state. On first interactive shell, zsh clones any missing plugins automatically.

Preview before applying: `chezmoi diff`, then `chezmoi apply`.

## Editing config

```bash
chezmoi edit --apply ~/.zshrc   # edit + deploy in one step
chezmoi cd                      # jump into the source tree (home/)
chezmoi diff                    # preview pending changes
chezmoi apply                   # deploy
```

## Structure

| Path | Purpose |
|------|---------|
| `home/dot_zshrc`, `home/dot_zshenv` | zsh entry points (→ `~/.zshrc`, `~/.zshenv`) |
| `home/dot_config/zsh/lib/*` | functions, env, options, plugins, completions, aliases, tmux, secrets |
| `home/dot_tmux.conf` (+ `dot_tmux.conf.d/claude.conf`) | tmux config |
| `home/dot_local/bin/executable_*` | `theme`, `zedw`, tmux helper scripts |
| `home/dot_claude/hooks/executable_*` | Claude Code hooks |
| `home/starship/` | theme palettes (read by `theme`; not deployed) |
| `home/run_*` | plugin bootstrap, completion + theme generation |
| `agents/`, `docs/`, `test/`, `macos/` | skill defs, design records, health check, macOS defaults |

## Theming

`theme set <name>` recolors starship + tmux + fzf together — 8 themes (neon-dreams,
synthwave-84, catppuccin-mocha, tokyo-night, outrun, vaporwave, neutral-engineering,
neutral-engineering-light). `theme list` / `theme next`. On WSL, sync Windows
Terminal too with `DOTFILES_THEME_WT=1`.

## Plugin management

```zsh
plugin update    # pull latest for all plugins
plugin compile   # byte-compile plugins (faster startup)
plugin list      # show installed plugins
plugin clean     # nuke the plugin cache (re-clones on next launch)
```

## Secrets

`~/.secrets` (operator-managed) holds the 1Password service-account token; app keys
render to `~/.config/zsh/secrets.env` at apply time via `onepasswordRead`.

## User-local overrides

`~/.zshrc-$USER` for machine-specific config (sourced last, not tracked).

## License

MIT
