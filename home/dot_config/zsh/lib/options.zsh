# options.zsh — shell options and key bindings

# ── history ──────────────────────────────────────────────────────────────────
setopt inc_append_history     # append each command immediately, don't wait for exit
setopt share_history          # share history across sessions
setopt hist_ignore_dups       # don't record an entry that matches the previous
setopt hist_ignore_all_dups   # delete old duplicate entries when a new one is added
setopt hist_find_no_dups      # searches skip duplicate matches
setopt hist_expire_dups_first # trim duplicates first when history overflows
setopt hist_ignore_space      # commands starting with a space aren't saved
setopt hist_reduce_blanks     # remove superfluous blanks before storing
setopt hist_verify            # show history expansions before running (safety for !!)

# ── directory navigation ─────────────────────────────────────────────────────
setopt auto_cd                # type a dir name (no `cd`) and it cd's there
setopt auto_pushd             # every cd pushes the prev dir onto the stack
setopt pushd_ignore_dups      # stack never contains the same dir twice
setopt pushd_silent           # don't print the stack after every pushd
setopt pushd_to_home          # `pushd` with no args goes home
setopt cdable_vars            # cd to the value of a variable (cd dotfiles → $dotfiles)

# ── globbing ─────────────────────────────────────────────────────────────────
setopt glob_dots              # include dotfiles in glob patterns
setopt extended_glob          # ^ ~ # negation/exclusion/etc
setopt numeric_glob_sort      # sort numeric filenames numerically (file10 after file2)
setopt no_nomatch             # pass unmatched globs through as literals

# ── completion ───────────────────────────────────────────────────────────────
setopt no_auto_menu           # require explicit TAB to open completion menu
setopt complete_in_word       # allow cursor in the middle of the word on completion
setopt always_to_end          # move cursor to end of word after completion
setopt list_packed            # pack the completion list tighter

# ── misc correctness / ergonomics ────────────────────────────────────────────
setopt no_beep
setopt prompt_subst           # allow $(…) and ${…} in PROMPT
setopt interactive_comments   # allow # comments at the interactive prompt
setopt hash_list_all
setopt noflowcontrol          # disable ^S/^Q flow control
setopt long_list_jobs         # show PID when suspending jobs

# ── key bindings (emacs baseline) ────────────────────────────────────────────
bindkey -e

# Word-wise navigation via Ctrl+arrow (xterm sequence)
bindkey ';5C' emacs-forward-word
bindkey ';5D' emacs-backward-word

# Partial-line history search on arrow keys:
# type `ssh ` then ↑/↓ to cycle only through commands starting with `ssh `.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search      # ↑
bindkey '^[[B' down-line-or-beginning-search    # ↓
bindkey '^P'   up-line-or-beginning-search      # Ctrl+p
bindkey '^N'   down-line-or-beginning-search    # Ctrl+n

# Home/End/Delete/PageUp/PageDown — work across terminals
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[5~' up-line-or-history             # PageUp
bindkey '^[[6~' down-line-or-history           # PageDown

# Ctrl+u — kill to beginning of line (zsh default kills the WHOLE line, match bash)
bindkey '^U' backward-kill-line

# Ctrl+space — accept autosuggestion without executing
bindkey '^ ' autosuggest-accept

# ── autoloads ────────────────────────────────────────────────────────────────
autoload -Uz zmv
autoload -Uz select-word-style && select-word-style bash  # path segments in word-wise edits
