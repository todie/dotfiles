# aliases.zsh — aliases and shell shims

alias sudo='/usr/bin/sudo'
alias grep='grep --color=auto'

# ls / eza — use eza if available, fall back to ls
_eza_flags='--color-scale --links --icons --git --group --changed'
if has eza; then
  alias list="eza $_eza_flags --all -l --classify --group-directories-first --color=auto --time-style=iso"
  alias tree="eza --tree"
  alias ls='eza --color=auto'
  alias ll='eza -l'
else
  alias list="ls --all -l --classify --group-directories-first --color=auto"
  alias tree='tree -C'
  alias ls='ls --color=always'
  alias ll='ls -l'
fi
unset _eza_flags

# s3cmd shim
has s3cmd && alias s3="s3cmd"
