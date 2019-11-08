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


if [[ -f /etc/environment ]]; then
	source /etc/environment
fi

if [[ -f /etc/zshrc ]]; then
	source /etc/zshrc
fi

# check for intel opt package
if [[ -d /opt/intel/parallel_studio_xe_2018/ ]]; then
  source /opt/intel/parallel_studio_xe_2018/psxevars.sh &> /dev/null
fi

# work hosts
if [[ "$(hostname)" == "ny4-collector-01" ]]; then
  export VOLERA_FH_HOME="${HOME}/workspace/SWFeedHandler"
  export ENV="NY4Dev"
  export PATH=$PATH:$VOLERA_FH_HOME/bin
fi

if [[ $(lsb_release -is) == "CentOS" ]]; then
  # -------------------------------
  # CentOS specific features
  # -------------------------------

  # alternative git
  [[ -f /opt/rh/rh-git29/enable ]] && source /opt/rh/rh-git29/enable

  # alternative gcc
  [[ -f /opt/rh/devtoolset-7/enable ]] && source /opt/rh/devtoolset-7/enable
fi

if [[ -d /snap/ ]]; then
	export PATH="/snap/bin:$PATH"
fi

# set up local go env if it exists
if [ -d ${HOME}/go ]; then 
  GOPATH=$HOME/go
  export PATH=$GOPATH/bin:$PATH
fi

# set up local ruby env if it exists
if [ -d ${HOME}/.gem ]; then
  GEM_HOME=~/.local/share/ruby
  GEM_PATH="$GEM_HOME:$GEM_PATH"
  export PATH="/home/ctodie/.gem/ruby/2.5.0/bin:$PATH"
  mkdir -p "$GEM_HOME"
fi

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

