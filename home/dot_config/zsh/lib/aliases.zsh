# aliases.zsh — aliases and shell shims
#
# Policy: NO command-hiding shorthands. We do not alias `g`→git, `k`→kubectl,
# `d`→docker, `gca`→git commit --amend, etc. Type the real command — it keeps
# shell history, scripts, and screen-shares readable, and never hides a
# non-trivial/destructive op behind two letters. Only these belong here:
#   • tool substitutions under the familiar name (ls→eza, cat→bat, top→btop)
#   • structural navigation (.., -)
#   • project cd-shortcuts and config-edit helpers

alias sudo='/usr/bin/sudo'
alias grep='grep --color=auto'

# ── directory navigation ────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'                      # jump back to previous dir

# mkdir + cd in one step
mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

# ── ls / eza — modern ls under the familiar name ────────────────────────────
_eza_flags='--color=auto --color-scale --links --icons --git --group --changed'
if has eza; then
  alias ls='eza --color=auto --icons'
  alias l='eza -l --icons --git'
  alias ll='eza -l --icons --git --group'
  alias la='eza -la --icons --git --group'
  alias list="eza $_eza_flags --all -l --classify --group-directories-first --time-style=iso"
  alias tree='eza --tree --icons --level=3'
  alias tree2='eza --tree --icons --level=2'
  alias tree4='eza --tree --icons --level=4'
else
  alias ls='ls --color=always'
  alias l='ls -l'
  alias ll='ls -l'
  alias la='ls -la'
  alias list='ls --all -l --classify --group-directories-first --color=auto'
  alias tree='tree -C'
fi
unset _eza_flags

# ── cat → bat ───────────────────────────────────────────────────────────────
if has bat; then
  alias cat='bat --paging=never --style=plain'
  alias catp='bat'                     # cat-with-pager (full bat)
  alias catn='bat --style=numbers'     # cat with line numbers
fi

# ── btop → top (system monitor under the familiar name) ─────────────────────
has btop && alias top='btop'

# ── kubecolor → kubectl (colorized kubectl under the familiar name) ──────────
# Same tool-substitution pattern as ls→eza / cat→bat: kubecolor is a drop-in
# kubectl wrapper that colorizes output and falls back to plain kubectl for any
# command it doesn't recognize. It auto-disables color when piped/non-tty, so
# scripts and `kubectl … | grep` stay clean. Completion is registered under
# `kubecolor` in completions.zsh; the `kubectl` word keeps its own completion.
has kubecolor && alias kubectl='kubecolor'

# ── zoxide (smart cd) ───────────────────────────────────────────────────────
# `z foo` jumps to the most-frecent dir matching foo; `zi` is interactive.
# Provided by `zoxide init` (env.zsh), not aliased here.

# ── clipboard (WSL2-friendly, matches tmux-copy script) ─────────────────────
if has clip.exe || has win32yank.exe; then
  if has win32yank.exe; then
    alias pbcopy='win32yank.exe -i --crlf'
    alias pbpaste='win32yank.exe -o'
  else
    alias pbcopy='clip.exe'
  fi
fi

# ── Zed on the Windows host (WSL) ────────────────────────────────────────────
# `zedw` opens paths in the Windows-host Zed via Zed's --wsl remoting. It's a
# real binary (bin/zedw, symlinked to ~/.local/bin by install.sh) — NOT an alias
# — so it also works as $EDITOR: `export EDITOR="zedw --wait"`. See `zedw` header.

# ── quick config edits ──────────────────────────────────────────────────────
alias zshrc='${EDITOR:-vim} ~/projects/dotfiles/zsh/.zshrc'
alias tmuxrc='${EDITOR:-vim} ~/projects/dotfiles/tmux/.tmux.conf'
alias starrc='${EDITOR:-vim} ~/projects/dotfiles/starship/base.toml'
alias reload='exec zsh'

# ── cd shortcuts to common projects (uses cdable_vars) ──────────────────────
export dotfiles="${HOME}/projects/dotfiles"
export pact="${HOME}/projects/pact"
export reach="${HOME}/projects/reach"
export reverie="${HOME}/projects/reverie"
