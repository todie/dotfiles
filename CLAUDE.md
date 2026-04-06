# dotfiles

Personal shell environment for `todie`. Structured for ongoing iteration.

## Layout

```
zsh/
  .zshrc          — entry point, sources modules in order
  lib/
    functions.zsh — utility functions (pinfo, has, download, unpack…)
    env.zsh       — PATH, XDG dirs, HISTFILE, EDITOR, starship
    options.zsh   — setopt, bindkey, autoloads
    plugins.zsh   — bare-metal plugin system + curated plugin list
    completions.zsh — per-tool completion setup
    aliases.zsh   — ls/eza shims, s3cmd alias, grep color
```

## Adding a dotfile

1. Drop it under the relevant directory (e.g. `git/.gitconfig`).
2. Add a `link` call in `install.sh`.
3. Commit: `feat(<scope>): add <what>`.

## Plugin policy

Keep the plugin list in `zsh/lib/plugins.zsh` **minimal** — only tools used daily.
Comment out optional plugins; don't delete them (they serve as documentation).

## Commit style

Conventional commits. Scope = the config domain being changed:
- `feat(zsh): ...`
- `fix(aliases): ...`
- `chore: ...`

## Install

```bash
git clone git@github.com:todie/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
exec zsh
```
