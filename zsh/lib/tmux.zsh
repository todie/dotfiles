# tmux.zsh — tmux integration for zsh
#
# - Aliases for common tmux ops
# - Auto-attach helper (opt-in via DOTFILES_TMUX_AUTOATTACH=1)
# - Project sessionizer keybinding (C-f, mirrors the in-tmux binding)
# - Quick session/window names

# ── Aliases ─────────────────────────────────────────────────────────────────
alias t='tmux'
alias ta='tmux attach -t'                            # ta <name>
alias tat='tmux attach -t'                           # ta(t)tach
alias tn='tmux new-session -s'                       # tn <name>
alias tns='tmux new-session -As'                     # attach-or-new
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'                      # tk <name>
alias tka='tmux kill-server'                         # nuke everything
alias tkw='tmux kill-window -t'
alias tsw='tmux switch-client -t'                    # tsw <name> (from inside tmux)

# Reattach to the most recently used session, or create a new one in cwd
ts() {
  if [[ -n "${TMUX:-}" ]]; then
    print "Already inside a tmux session ($TMUX_PANE)" >&2
    return 1
  fi
  local last
  last=$(tmux list-sessions -F '#{session_last_attached} #{session_name}' 2>/dev/null \
    | sort -rn | awk 'NR==1 {print $2}')
  if [[ -n "$last" ]]; then
    tmux attach-session -t "$last"
  else
    tmux new-session -s "$(basename "$PWD")"
  fi
}

# ── Sessionizer (mirrors C-f inside tmux) ──────────────────────────────────
# Bind to C-f at the shell level so it works in or out of tmux
if has tmux-sessionizer; then
  bindkey -s '^f' '^utmux-sessionizer^M'
fi

# ── Auto-attach to a session named after the current dir ───────────────────
# Opt-in: set DOTFILES_TMUX_AUTOATTACH=1 in ~/.zshrc-${USER} to enable.
# Skipped over SSH-without-explicit-request, in subshells, in VS Code term.
if [[ "${DOTFILES_TMUX_AUTOATTACH:-0}" == "1" ]] \
   && [[ -z "${TMUX:-}" ]] \
   && [[ -z "${VSCODE_INJECTION:-}" ]] \
   && [[ "${TERM_PROGRAM:-}" != "vscode" ]] \
   && [[ $- == *i* ]]; then
  local _session
  _session=$(basename "$PWD")
  tmux new-session -A -s "$_session" 2>/dev/null || true
fi

# ── In-tmux helpers ────────────────────────────────────────────────────────
# Rename window to current command via PROMPT pre-exec
if [[ -n "${TMUX:-}" ]]; then
  _tmux_set_window_to_command() {
    local cmd="${1%% *}"
    [[ -n "$cmd" ]] && tmux rename-window "$cmd" 2>/dev/null
  }
  _tmux_set_window_to_dir() {
    tmux rename-window "$(basename "$PWD")" 2>/dev/null
  }
  # Only auto-rename if user hasn't manually renamed
  # autoload -Uz add-zsh-hook
  # add-zsh-hook preexec _tmux_set_window_to_command
  # add-zsh-hook precmd _tmux_set_window_to_dir
  # ^ leave commented — auto-rename is opinionated. uncomment to enable.

  alias bcast='tmux setw synchronize-panes'   # broadcast to all panes (toggle)
  alias zoom='tmux resize-pane -Z'             # zoom toggle
fi
