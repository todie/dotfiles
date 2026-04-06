# dotfiles

Minimal, modular zsh environment. Clone, run `install.sh`, done.

## Requirements

- zsh
- git (for plugin auto-clone)
- [starship](https://starship.rs) (prompt, optional but recommended)
- [eza](https://github.com/eza-community/eza) (ls replacement, optional)

## Install

```bash
git clone git@github.com:todie/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
exec zsh
```

The install script symlinks `~/.zshrc` into place. Existing files are backed up
to `~/.dotfiles-backup/<timestamp>/` before being replaced.

On first launch zsh will clone any missing plugins automatically.

## Structure

| Path | Purpose |
|------|---------|
| `zsh/.zshrc` | Entry point — sources modules in order |
| `zsh/lib/functions.zsh` | Utility functions (`pinfo`, `has`, `download`, …) |
| `zsh/lib/env.zsh` | XDG dirs, PATH, EDITOR, starship init |
| `zsh/lib/options.zsh` | `setopt`, `bindkey`, autoloads |
| `zsh/lib/plugins.zsh` | Bare-metal plugin system + plugin list |
| `zsh/lib/completions.zsh` | Per-tool completion setup |
| `zsh/lib/aliases.zsh` | `ls`/`eza` shims, grep, s3cmd |

## User-local overrides

Create `~/.zshrc-$USER` for machine-specific config (secrets, work tokens, etc.).
That file is sourced last and is intentionally not tracked.

## Plugin management

```zsh
plugin update    # pull latest for all plugins
plugin compile   # byte-compile plugins (faster startup)
plugin list      # show installed plugins
plugin clean     # nuke the plugin cache (will re-clone on next launch)
```

## License

MIT
