DOTFILES_ZSH_COMPLETIONS=~/.local/share/zsh/completions.d
if [[ -d ${DOTFILES_ZSH_COMPLETIONS} ]]; then
  fpath+=${DOTFILES_ZSH_COMPLETIONS}
fi

autoload -Uz compinit

# Order in which completion mechanisms will be tried:
# 1. Try completing the results of an old list
#    ( for use with history completion on ctrl-space )
# 2. Try to complete using context-sensitive completion
# 3. Try interpretting the typed text as a pattern and matching it against the
#    possible completions in context
# 4. Try completing the word just up to the cursor, ignoring anything past it.
# 5. Try combining the effects of completion and correction.
zstyle ':completion:*' completer _oldlist _complete _match \
                                 _expand _prefix _approximate

# Enable caching
zstyle ':completion:*' use-cache on
zstyle ':completion:*' list-prompt %S%L -- More --%s
zstyle ':completion:*:warnings' format '%BNo matches for: %d%b'

# Don't complete backup files as executables
zstyle ':completion:*:complete:-command-::commands' ignored-patterns '*\~'

# If I don't have `executable`, don't complete to the _executable completer
zstyle ':completion:*:functions' ignored-patterns '_*'

# Match lowercase letters to uppercase letters and dashes to underscores
#zstyle ':completion:*' matcher-list 'm:{a-z-}={A-Z_}' 'r:|.=** r:|=*'
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'


# Try to use verbose listing if possible
zstyle ':completion:*' verbose true

# Allows /u/l/b<TAB> to menu complete as though you typed /u*/l*/b*<TAB>
zstyle ':completion:*:paths' expand suffix

# Menu complete on ambiguous paths
#zstyle ':completion:*:paths' list-suffixes true

# Have '/home//<TAB>' list '/home/*' rather than '/home/*/*'
zstyle ':completion:*:paths' squeeze-slashes false

# Enter 'menu selection' if there are at least 2 choices while completing
zstyle ':completion:*' menu select=2

# what does this do
zstyle ':completion:*' special-dirs true

# avoid editing certain files in vim
zstyle ':completion:*:*:(vi|vim):*:*' \
    file-patterns '*~(*.o|*~|*.old|*.bak|*.pro|*.zwc|*.swp):regular-files' \
                  '(*~|*.bak|*.old):backup-files' \
                  '(*.o|*.pro|*.zwc|*.swp):hidden-files'

zstyle -e ':completion:*:(ssh|scp|sftp|rsh|rsync):hosts' hosts 'reply=(${=${${(f)"$(cat {/etc/ssh_,~/.ssh/known_}hosts(|2)(N) /dev/null)"}%%
[# ]*}//,/ })'

# Use colors in tab completion
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Add a space to expansions
zstyle ':completion:*:expand:*' add-space true

# kill
zstyle ':completion:*:*:kill:*' command 'ps -u$USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;36=0=01'
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*' force-list always

# man
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.(^1*)' insert-sections true

