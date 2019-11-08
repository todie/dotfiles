#Bail out if we're not an interactive shell
[[ -n "${DOTFILES_PROFILE}" ]] && zmodload zsh/zprof
[[ -o nointeractive ]] && return

# Process init directory
for file in ~/.local/share/zsh/init.d/*.zsh; source $file

unsetopt beep                                           # Turn off bell noise
setopt prompt_subst
setopt inc_append_history
setopt share_history
setopt histignorespace
