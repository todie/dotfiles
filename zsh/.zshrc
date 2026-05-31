# ${HOME}/.zshrc: user profile for zsh (zsh(1))
# Author: Christian M. Todie <ctodie@coreweave.com>

export GPG_TTY=$TTY
export DOTFILES_ZSH_DEBUG="${DOTFILES_ZSH_DEBUG:-0}"
export DOTFILES_ZSH_CACHE=${XDG_CACHE_HOME:-~/.cache}/zsh

# Completion fpath must be set BEFORE compinit so cached _tool files autoload.
fpath=("$HOME/.zsh/completions" $fpath)

# Daily-cached compinit. Rebuilding the dump (compaudit + compdump) costs
# ~200ms and runs on EVERY start by default. Instead: regenerate at most once
# per 24h; otherwise load the existing dump with -C (skips the security audit).
# Shared dump path ($ZCOMPDUMP) is reused by completions.zsh's regen.
export ZCOMPDUMP="${DOTFILES_ZSH_CACHE}/.zcompdump"
[[ -d $DOTFILES_ZSH_CACHE ]] || mkdir -p "$DOTFILES_ZSH_CACHE"
autoload -U +X compinit
() {
  setopt local_options extended_glob
  if [[ -n $ZCOMPDUMP(#qNmh-24) ]]; then
    compinit -C -d "$ZCOMPDUMP"      # fresh dump (<24h) — trust it, skip audit
  else
    compinit -u -d "$ZCOMPDUMP"      # stale/missing — full rebuild
  fi
}

# ~w => Windows home on WSL
[[ -z $dotfiles_win_home ]] || hash -d w=$dotfiles_win_home

# Resolve the real location of this file (survives symlinking).
DOTFILES_ZSH_DIR="${${(%):-%x}:A:h}"

# Load modules in dependency order.
for _module in \
  $DOTFILES_ZSH_DIR/lib/functions.zsh \
  $DOTFILES_ZSH_DIR/lib/env.zsh \
  $DOTFILES_ZSH_DIR/lib/options.zsh \
  $DOTFILES_ZSH_DIR/lib/plugins.zsh \
  $DOTFILES_ZSH_DIR/lib/completions.zsh \
  $DOTFILES_ZSH_DIR/lib/aliases.zsh \
  $DOTFILES_ZSH_DIR/lib/tmux.zsh \
  $DOTFILES_ZSH_DIR/lib/secrets.zsh; do
  [[ -r $_module ]] && source "$_module"
done
unset _module

# coreweave dev-shell integration.
[[ -r /usr/local/share/dev-shell/dev-shell ]] && source /usr/local/share/dev-shell/dev-shell

# User-local overrides — not tracked in dotfiles.
[[ -f "${HOME}/.zshrc-${USER}" ]] && source "${HOME}/.zshrc-${USER}"

# Added by Pilot installer
export PATH="$HOME/.local/bin:$PATH"

# --- ssh-agent ---
# Removed: SSH now routed through 1Password via ~/.zshrc-ctodie (aliases
# ssh/ssh-add to ssh.exe/ssh-add.exe per WSL integration docs).

# Prefer stored gh OAuth token over inherited GITHUB_TOKEN PAT (which lacks SSO access to cerebral-work/*)
gh() { GITHUB_TOKEN= command gh "$@"; }

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/home/ctodie/google-cloud-sdk/path.zsh.inc' ]; then . '/home/ctodie/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/home/ctodie/google-cloud-sdk/completion.zsh.inc' ]; then . '/home/ctodie/google-cloud-sdk/completion.zsh.inc'; fi


# claude yolo (sandboxed/throwaway dirs only)
alias cy="claude --dangerously-skip-permissions"

# bashcompinit already initialized in lib/env.zsh; just register the completion.
complete -o nospace -C /home/ctodie/.local/bin/terraform terraform
