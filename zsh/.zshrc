# ${HOME}/.zshrc: user profile for zsh (zsh(1))
# Author: Christian M. Todie <ctodie@coreweave.com>

export GPG_TTY=$TTY
export DOTFILES_ZSH_DEBUG="${DOTFILES_ZSH_DEBUG:-0}"
export DOTFILES_ZSH_CACHE=${XDG_CACHE_HOME:-~/.cache}/zsh

autoload -U +X compinit && compinit -u

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
  $DOTFILES_ZSH_DIR/lib/aliases.zsh; do
  [[ -r $_module ]] && source "$_module"
done
unset _module

# coreweave dev-shell integration.
[[ -r /usr/local/share/dev-shell/dev-shell ]] && source /usr/local/share/dev-shell/dev-shell

# User-local overrides — not tracked in dotfiles.
[[ -f "${HOME}/.zshrc-${USER}" ]] && source "${HOME}/.zshrc-${USER}"
