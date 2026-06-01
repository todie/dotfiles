# chezmoi migration — execution plan (teed up, not started)

_Builds on `docs/install-mechanism.md` (the decision) and the `spike/chezmoi`
branch (proof: source→apply, no symlinks, 1Password + templating verified).
chezmoi is installed (`~/.local/bin/chezmoi` v2.70.4)._

## Decisions to settle FIRST (these gate the mechanical work)
1. **Source location** — keep the repo at `~/projects/dotfiles` as the chezmoi
   source (`chezmoi --source`), or adopt the default `~/.local/share/chezmoi`?
   Recommend: keep the repo path; set `sourceDir` in chezmoi config.
2. **Theme source files** — `theme` reads `starship/themes/*.toml` + `base.toml`
   at runtime from `$DOTFILES_DIR`. Under chezmoi these aren't "deployed" files;
   they must stay readable. Options: keep them in the source tree and point the
   installed `theme` at `$(chezmoi source-path)/starship/...`, or ship them to
   `~/.config/dotfiles-themes/`. **Resolve before converting starship.**
3. **`DOTFILES_ZSH_DIR`** — `.zshrc` resolves its own dir to source `lib/*`. Under
   the copy model, deploy libs to `~/.config/zsh/lib/` and set
   `DOTFILES_ZSH_DIR=~/.config/zsh` (or use `ZDOTDIR`).

## Mechanical conversion (incremental — keep install.sh working until cutover)
| Repo | chezmoi source name | Deploys to |
|---|---|---|
| `zsh/.zshrc` | `dot_zshrc.tmpl` | `~/.zshrc` |
| `zsh/lib/*.zsh` | `dot_config/zsh/lib/*` | `~/.config/zsh/lib/` |
| `zsh/completions/_*` | `dot_local/share/zsh/completions/*` | `~/.local/share/...` |
| `tmux/.tmux.conf` | `dot_tmux.conf` | `~/.tmux.conf` |
| `tmux/claude.conf` | `dot_tmux.conf.d/claude.conf` | `~/.tmux.conf.d/` |
| `tmux/scripts/*`, `bin/*` | `dot_local/bin/executable_*` | `~/.local/bin/` |
| `claude/hooks/*` | `dot_claude/hooks/executable_*` | `~/.claude/hooks/` |
| `starship/scripts/theme` | `dot_local/bin/executable_theme` | `~/.local/bin/theme` |

## Then
4. **Templating** — replace runtime WSL guards (`WSL_DISTRO_NAME`, `has` cascades)
   with `{{ if eq .chezmoi.os "linux" }}` / `.chezmoi.kernel`; per-machine via
   `.chezmoidata`. (Spike proved `DOTFILES_IS_WSL` detection works.)
5. **Secrets** — replace `secrets.zsh` `op://` map + `render-zed-settings` with
   `{{ onepasswordRead "op://..." }}` templates, `[onepassword] mode = "service"`
   (token already in `~/.secrets`). Spike rendered `~/.secrets` at 0600 ✓.
6. **Imperative install bits** → `run_once_`/`run_onchange_` scripts:
   plugin bootstrap, completion generation, `theme set` (palette + tmux/fzf/WT
   fragments + starship.toml).
7. **Cutover** — `chezmoi init` from the repo → `chezmoi diff` vs live `~`
   (verbatim files should diff empty; the symlink→realfile flip is the only
   change) → `chezmoi apply` → verify with `test/zsh-health.zsh`.
8. Retire the `install.sh` symlink section (keep as fallback during transition).

## Shape & risk
~40 files; mostly mechanical renaming. The three decisions above + secrets
templating are the only real design work. Do it as its own PR, incrementally,
with `chezmoi diff` proving parity at each step. `spike/chezmoi` has a working
reference for tmux + a zsh module + a secret.
