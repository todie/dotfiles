# options.zsh — shell options and key bindings

# ── setopt ───────────────────────────────────────────────────────────────────
setopt glob_dots           # include dotfiles in glob patterns
setopt no_auto_menu        # require explicit TAB to open completion menu
setopt no_beep
setopt prompt_subst
setopt inc_append_history  # append each command immediately
setopt share_history       # share history across sessions
setopt hist_ignore_space   # commands starting with space aren't saved
setopt no_nomatch          # don't error on unmatched globs
setopt interactive_comments
setopt hash_list_all
setopt complete_in_word
setopt noflowcontrol       # disable ^S/^Q flow control

# ── key bindings (emacs style) ───────────────────────────────────────────────
bindkey -e
bindkey ';5C' emacs-forward-word
bindkey ';5D' emacs-backward-word

# ── autoloads ────────────────────────────────────────────────────────────────
autoload -Uz zmv
