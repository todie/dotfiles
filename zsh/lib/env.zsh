# env.zsh — environment variables and directory bootstrapping

# ── XDG directories ──────────────────────────────────────────────────────────
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# ── local bin / man / completions ────────────────────────────────────────────
BIN_DIR=~/.local/bin
COMP_DIR=~/.local/share/zsh/completions
MAN_DIR=~/.local/man

for _dir in "$BIN_DIR" "$COMP_DIR" "$MAN_DIR" "${XDG_CACHE_HOME}/zsh"; do
  [[ -d $_dir ]] || mkdir -p "$_dir"
done
unset _dir

path+=("$BIN_DIR")
fpath+=("$COMP_DIR")
manpath+=("$MAN_DIR")

# ── history ──────────────────────────────────────────────────────────────────
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE="${XDG_CACHE_HOME}/zsh-history"

# ── editor — prefer VS Code, fall back gracefully ────────────────────────────
if has code; then
  VSCODE_BIN="$(which code)"
  export EDITOR="$VSCODE_BIN"
  export KUBE_EDITOR="$VSCODE_BIN -w"
  export GIT_EDITOR="$VSCODE_BIN -w"

  # sudoedit with VS Code
  sucode() { EDITOR="$VSCODE_BIN -w" command -- sudo -e "$@"; }
elif has nvim; then
  export EDITOR=nvim
elif has vim; then
  export EDITOR=vim
elif has emacs; then
  export EDITOR=emacs
elif has nano; then
  printf "${RED}WARNING:${NO_COLOR} falling back to nano. Install a real editor.\n"
  export EDITOR=nano
fi

# ── misc ─────────────────────────────────────────────────────────────────────
export CLICOLOR_FORCE=1
export KEYTIMEOUT=1
export LIBRARY_LOG_TIMESTAMP=1
export PAGER="less -RF"

# vault completion (requires vault binary in BIN_DIR)
autoload -U +X bashcompinit && bashcompinit
[[ -x "${BIN_DIR}/vault" ]] && complete -o nospace -C "${BIN_DIR}/vault" vault

# ── modern tool init ─────────────────────────────────────────────────────────

# zoxide — smart cd (`z foo` jumps to the most-frecent dir matching `foo`)
# Adds `z`, `zi` (fzf-interactive), and hooks chpwd to track dir frecency.
has zoxide && eval "$(zoxide init zsh)"

# fzf — fuzzy finder key bindings + completion
# Ctrl-R → history fzf, Ctrl-T → file fzf, Alt-C → cd fzf
if has fzf; then
  # Key bindings + completion live with the fzf install
  [[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
  # FZF default look matches the synthwave/neon-dreams palette
  export FZF_DEFAULT_OPTS="
    --height 60% --layout=reverse --border --ansi
    --color=fg:#a89bd6,bg:-1,hl:#ff2975,fg+:#ffffff,bg+:#160b3b,hl+:#ff2975
    --color=info:#00f0ff,prompt:#ff2975,pointer:#ff2975,marker:#5af78e
    --color=spinner:#b026ff,header:#4a3f6b,border:#2d1f4f,label:#a89bd6
    --prompt='▸ ' --pointer='▲' --marker='◉'
  "
  # Use fd for file+dir listings if available (respects .gitignore, fast)
  if has fd; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi
fi

# bat — cat replacement with syntax highlighting
if has bat; then
  export BAT_THEME="OneHalfDark"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# delta — git diff viewer (configured in ~/.gitconfig, this just ensures
# the binary is discoverable)
# (delta is used via git's [core] pager — no env var needed here)

# starship prompt — keep near end of env setup so it's the final PROMPT owner
has starship && eval "$(starship init zsh)"
