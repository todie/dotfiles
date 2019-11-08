umask 022
#[[ -f ~/.config/zsh/zplug/init.zsh ]] || return

# Skip zplug initialization if it's not available
[[ -f ~/.local/share/zsh/zplug/init.zsh ]] || return
source ~/.local/share/zsh/zplug/init.zsh
# ---
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-completions"
zplug "zsh-users/zsh-history-substring-search", defer:2
zplug "zsh-users/zsh-syntax-highlighting", defer:3
# ---
zplug "DFurnes/purer", use:pure.zsh, from:github, as:theme
PURE_PROMPT_SYMBOL="»"
PURE_PROMPT_VICMD_SYMBOL="«"
PURE_GIT_DOWN_ARROW="↑"
PURE_GIT_UP_ARROW="↓"
# ---
zplug "tarruda/zsh-autosuggestions", use:"zsh-autosuggestions.zsh"
zplug "mafredri/zsh-async", from:github
zplug "lib/key-bindings", from:oh-my-zsh
zplug "lib/directories", from:oh-my-zsh
zplug "lib/tmux", from:oh-my-zsh
# ---
zplug "tmux-plugins/tpm"

# Install plugins that haven't been installed
if ! zplug check --verbose; then
  printf "Install? [y/N]: "
  if read -q; then
    echo; zplug install
  else
    echo
  fi
fi

# Source plugins && add commands to $PATH
zplug load

