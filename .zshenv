export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"

export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history
export CLICOLOR_FORCE=1
export KEYTIMEOUT=1
export VISUAL="nvim"
export EDITOR="$VISUAL"

export PATH="$HOME/.local/bin:/usr/local/bin/:/usr/local/sbin/:$PATH"

(( $+commands[npm] )) && npm config set prefix "${HOME}/.local"

# Pull in common functionality
source ~/.local/share/sh/functions.sh

fpath=(
  ~/.local/share/zsh/functions.d
  ~/.local/share/sh/functions.sh
  "${fpath[@]}"
)


# moved these here so shells have access to them
export DOTFILES_ZSH_FUNCTIONS=~/.local/share/zsh/functions.d

if [[ -d ${DOTFILES_ZSH_FUNCTIONS} ]]; then
  fpath+="${DOTFILES_ZSH_FUNCTIONS}"
  for func in ${DOTFILES_ZSH_FUNCTIONS}/_*(N:t); do
    autoload -Uz "${func}"
  done

  for func in ${DOTFILES_ZSH_FUNCTIONS}/[^_]*(N); do
    source "${func}"
  done
fi

export LIBRARY_LOG_TIMESTAMP=1

mux() {
  tmuxinator "$@" 2>/dev/null
}

alias sudo='/usr/bin/sudo'
alias tssh='env TERM=screen-256color ssh'

alias edit='nvim'
alias vi='nvim'
alias vim='nvim'

alias ls='ls -h --sort=extension --group-directories-first --color=auto'
alias ll='ls -hl --sort=extension --group-directories-first --color=auto'
alias la='ls -hla --sort=extension --group-directories-first --color=auto'
alias lp='ls -hla --sort=extension --group-directories-first --color=yes | less -R'
alias mdb='mongo -u $USER -p --authenticationDatabase admin'

alias grep='grep --color=auto'
alias df="df -Tha --total"
alias du="du -ach"
alias free="free -mt"
alias ps="ps auxf"

