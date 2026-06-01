# claude.zsh — `cc`: low-friction control for multiple Claude Code tmux sessions.
#
# Pairs with the tmux glance (~/.local/bin/tmux-claude-state + claude.conf).
# Data comes straight from tmux in single calls — claude panes are identified by
# #{pane_current_command}, and per-window state by the @claude_glyph option the
# glance already maintains (◉ = waiting). No process scans, no caches, no fragile
# command-substitutions inside read loops.
#
#   cc            fzf picker of live Claude sessions (project · window) → jump
#   cc go         jump to a session that needs you (a ◉ window) else first claude
#   cc new [dir]  open a window named after dir (default $PWD), launch claude
#   cc <dir>      shorthand for `cc new <dir>`

_cc_need_tmux() { [[ -n "$TMUX" ]] || { print -u2 "cc: not inside tmux"; return 1; }; }

_cc_new() {
  _cc_need_tmux || return 1
  local dir="${1:-$PWD}"
  [[ -d "$dir" ]] || { print -u2 "cc: no such dir: $dir"; return 1; }
  tmux new-window -n "${dir:t}" -c "$dir"
  tmux send-keys "claude" Enter
}

# "pane<TAB>display" for each Claude pane. One tmux call piped to awk — awk does
# the filter (command==claude), basename, and formatting in a single process, so
# there's no per-row shell command-substitution to trip over.
_cc_rows() {
  tmux list-panes -a -F '#{pane_id}	#{window_index}:#{window_name}	#{pane_current_path}	#{pane_current_command}' 2>/dev/null \
    | awk -F'\t' '$4=="claude"{ n=split($3,p,"/"); printf "%s\t%-20s %s\n", $1, p[n], $2 }'
}

_cc_ls() {
  _cc_need_tmux || return 1
  local rows sel target
  rows=$(_cc_rows)
  [[ -n "$rows" ]] || { print "no active claude sessions"; return 0; }
  sel=$(printf '%s\n' "$rows" \
        | fzf --with-nth=2.. --delimiter=$'\t' --height=40% --reverse \
              --prompt='claude ❯ ' --header='enter: jump') || return 0
  [[ -n "$sel" ]] || return 0
  target="${sel%%$'\t'*}"
  tmux select-window -t "$target" 2>/dev/null
  tmux select-pane   -t "$target" 2>/dev/null
}

_cc_go() {
  _cc_need_tmux || return 1
  local target
  # a window the glance marked waiting (◉); else the first Claude pane.
  target=$(tmux list-windows -a -F '#{window_id}	#{@claude_glyph}' 2>/dev/null \
           | awk -F'\t' '$2 ~ /◉/{print $1; exit}')
  [[ -n "$target" ]] || target=$(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}' 2>/dev/null \
           | awk -F'\t' '$2=="claude"{print $1; exit}')
  [[ -n "$target" ]] || { print "no active claude sessions"; return 0; }
  tmux select-window -t "$target" 2>/dev/null
  tmux select-pane   -t "$target" 2>/dev/null
}

cc() {
  local sub="${1:-ls}"
  case "$sub" in
    ls|list|l|"") _cc_ls ;;
    go|g)         _cc_go ;;
    new|n)        shift; _cc_new "$@" ;;
    -h|--help)    print -- "cc [ls | go | new <dir>]  ·  cc <dir> = new" ;;
    *)            _cc_new "$sub" ;;   # `cc <dir>` shorthand
  esac
}
