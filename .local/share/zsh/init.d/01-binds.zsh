# ensure terminal is in application mode
if (( ${+terminfo[smkx]} )) && (( ${+terminfo[rmkx]} )); then
  function zle-line-init() {
    echoti smkx
  }

  function zle-line-finish() {
    echoti rmkx
  }

  zle -N zle-line-init
  zle -N zle-line-finish
fi

autoload zkbd
bindkey -v

ZSH_KBD_SOURCE=~/.local/share/zsh/zkbd.d/$TERM
if [[ -f $ZSH_KBD_SOURCE ]]; then
  source $ZSH_KBD_SOURCE
else
  echo "WARNING: Keybindings may not be set correctly!"
  echo "Execute \`zkbd\` to create bindings."
fi

[[ -n "${key[Home]}" ]]    && bindkey "${key[Home]}"    beginning-of-line
[[ -n "${key[End]}" ]]     && bindkey "${key[End]}"     end-of-line
[[ -n "${key[Insert]}" ]]  && bindkey "${key[Insert]}"  overwrite-mode
[[ -n "${key[Delete]}" ]]  && bindkey "${key[Delete]}"  delete-char
[[ -n "${key[Up]}" ]]      && bindkey "${key[Up]}"      up-line-or-search
[[ -n "${key[Down]}" ]]    && bindkey "${key[Down]}"    down-line-or-search
[[ -n "${key[Left]}" ]]    && bindkey "${key[Left]}"    backward-char
[[ -n "${key[Right]}" ]]   && bindkey "${key[Right]}"   forward-char

[[ -n "${key[C-Up]}" ]]    && bindkey "${key[C-Up]}"    history-beginning-search-backward
[[ -n "${key[C-Down]}" ]]  && bindkey "${key[C-Down]}"  history-beginning-search-forward
[[ -n "${key[C-Left]}" ]]  && bindkey "${key[C-Left]}"  backward-word
[[ -n "${key[C-Right]}" ]] && bindkey "${key[C-Right]}" forward-word

[[ -n "${key[C-A]}" ]]     && bindkey "${key[C-A]}"			beginning-of-line
[[ -n "${key[C-E]}" ]]     && bindkey "${key[C-E]}"			end-of-line

[[ -n "${key[C-R]}" ]]     && bindkey "${key[C-R]}"     history-incremental-search-backward
[[ -n "${key[C-T]}" ]]     && bindkey "${key[C-T]}"     history-incremental-search-forward
[[ -n "${key[C-U]}" ]]     && bindkey "${key[C-U]}"     backward-kill-line

bindkey "^A" beginning-of-line
bindkey "^E" end-of-line
bindkey "^K" kill-line
bindkey "^U" backward-kill-line
bindkey "^L" clear-screen
bindkey "^R" history-incremental-search-backward
bindkey "^W" backward-kill-word

if [[ "${terminfo[kcbt]}" != "" ]]; then
  bindkey "^${terminfo[kcbt]}" reverse-menu-complete
fi

bindkey '^?' backward-delete-char                     # [Backspace] - delete backward

# This inserts a tab after completing a redirect. You want this.
# (Source: http://www.zsh.org/mla/users/2006/msg00690.html)
self-insert-redir() {
  integer l=$#LBUFFER
  zle self-insert
  (( $l >= $#LBUFFER )) && LBUFFER[-1]=" $LBUFFER[-1]"
}

zle -N self-insert-redir
for op in \| \< \> \& ; do
  bindkey "$op" self-insert-redir
done
