# aliases.zsh — aliases and shell shims

alias sudo='/usr/bin/sudo'
alias grep='grep --color=auto'

# ── directory navigation ────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'                      # jump back to previous dir
alias d='dirs -v | head -20'           # numbered dir stack (for `cd -N`)

# mkdir + cd in one step
mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

# ── ls / eza — eza if available, fall back to ls ────────────────────────────
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

# ── find → fd ───────────────────────────────────────────────────────────────
has fd && alias f='fd'

# ── grep → rg (keep grep alias for color; rg is its own command) ────────────
has rg && alias rgf='rg --files'

# ── zoxide (smart cd) ───────────────────────────────────────────────────────
# `z foo` jumps to the most-frecent dir matching foo; `zi` is interactive.
# Keep cd available so muscle memory still works.

# ── git — quick shims (full config lives in ~/.gitconfig) ──────────────────
if has git; then
  alias g='git'
  alias gs='git status -sb'
  alias gd='git diff'
  alias gds='git diff --staged'
  alias gl='git log --oneline --graph --decorate -20'
  alias gll='git log --oneline --graph --decorate --all -30'
  alias gp='git push'
  alias gpl='git pull --rebase --autostash'
  alias gco='git checkout'
  alias gcb='git checkout -b'
  alias gb='git branch'
  alias ga='git add'
  alias gaa='git add -A'
  alias gc='git commit'
  alias gcm='git commit -m'
  alias gca='git commit --amend --no-edit'
fi

# ── docker ───────────────────────────────────────────────────────────────────
if has docker; then
  alias d='docker'
  alias dc='docker compose'
  alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
  alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
  alias dimg='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"'
fi

# ── kubectl ──────────────────────────────────────────────────────────────────
if has kubectl; then
  alias k='kubectl'
  alias kg='kubectl get'
  alias kd='kubectl describe'
  alias kl='kubectl logs'
  alias kx='kubectl config use-context'
  alias kns='kubectl config set-context --current --namespace'
fi

# ── s3cmd shim ───────────────────────────────────────────────────────────────
has s3cmd && alias s3='s3cmd'

# ── clipboard (WSL2-friendly, matches tmux-copy script) ─────────────────────
if has clip.exe || has win32yank.exe; then
  if has win32yank.exe; then
    alias pbcopy='win32yank.exe -i --crlf'
    alias pbpaste='win32yank.exe -o'
  else
    alias pbcopy='clip.exe'
  fi
fi

# ── json + yaml ──────────────────────────────────────────────────────────────
has jq && alias j='jq'
has yq && alias y='yq'

# ── quick paths ──────────────────────────────────────────────────────────────
alias zshrc='${EDITOR:-vim} ~/projects/dotfiles/zsh/.zshrc'
alias tmuxrc='${EDITOR:-vim} ~/projects/dotfiles/tmux/.tmux.conf'
alias starrc='${EDITOR:-vim} ~/projects/dotfiles/starship/base.toml'
alias reload='exec zsh'

# ── cd shortcuts to common projects (uses cdable_vars) ──────────────────────
export dotfiles="${HOME}/projects/dotfiles"
export pact="${HOME}/projects/pact"
export reach="${HOME}/projects/reach"
