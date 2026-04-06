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

# starship prompt — keep near end of env setup
has starship && eval "$(starship init zsh)"
