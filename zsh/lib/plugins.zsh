# plugins.zsh — bare-metal plugin system
# Inspired by https://github.com/mattmc3/zsh_unplugged

# ── plugin machinery ─────────────────────────────────────────────────────────
ZPLUGINDIR="${ZPLUGINDIR:-${DOTFILES_ZSH_CACHE}/plugins}"

plugin-load() {
  local repo plugin_name plugin_dir initfile initfiles
  for repo in "$@"; do
    plugin_name="${repo:t}"
    plugin_dir="$ZPLUGINDIR/$plugin_name"
    initfile="$plugin_dir/$plugin_name.plugin.zsh"
    if [[ ! -d $plugin_dir ]]; then
      pinfo "Cloning $repo"
      git clone -q --depth 1 --recursive --shallow-submodules \
        "git@github.com:${repo}.git" "$plugin_dir" 2>/dev/null || \
      git clone -q --depth 1 --recursive --shallow-submodules \
        "https://github.com/${repo}" "$plugin_dir" 2>/dev/null
    fi
    if [[ ! -e $initfile ]]; then
      initfiles=($plugin_dir/*.plugin.{z,}sh(N) $plugin_dir/*.{z,}sh{-theme,}(N))
      (( ${#initfiles[@]} > 0 )) || { pwarn "Plugin has no init file: $repo"; continue; }
      ln -s "${initfiles[1]}" "$initfile"
    fi
    fpath+="$plugin_dir"
    (( $+functions[zsh-defer] )) && zsh-defer . "$initfile" || . "$initfile"
  done
}

plugin-compile() {
  autoload -U zrecompile
  local f
  for f in "$ZPLUGINDIR"/**/*.zsh{,-theme}(N); do
    pinfo "compiling $f"
    zrecompile -pq "$f"
  done
}

plugin-update() {
  for d in "$ZPLUGINDIR"/*/.git(/); do
    pinfo "Updating ${d:h:t}..."
    git -C "${d:h}" pull --ff --recurse-submodules --depth 1 --rebase --autostash
  done
}

plugin-clean() { rm -rf "$ZPLUGINDIR"; }

plugin-list() {
  if [[ ! -d $ZPLUGINDIR ]]; then
    pinfo "No plugins installed."
    return
  fi
  for d in "$ZPLUGINDIR"/*/.git; do
    git -C "${d:h}" remote get-url origin
  done
}

plugin-help() {
  pinfo "Usage: ${BOLD}${GREEN}plugin${NO_COLOR} load|update|compile|list|clean"
}

_plugin() {
  local line state
  _arguments -C "1: :->cmds" "*::arg:->args"
  case "$state" in
    cmds)
      _values "plugin command" \
        "load[Load plugins]" \
        "update[Update all plugins]" \
        "compile[Compile plugins for faster load]" \
        "list[List installed plugins]" \
        "clean[Remove all plugins]"
      ;;
  esac
}

plugin() {
  local subcommand="$1"
  case "$subcommand" in
    ""|"-h"|"--help") plugin-help ;;
    *)
      shift
      plugin-"${subcommand}" "$@"
      if (( $? == 127 )); then
        perror "'$subcommand' is not a known subcommand."
        pinfo "Run 'plugin --help' for usage."
        return 1
      fi
      ;;
  esac
}
compdef _plugin plugin

# ── plugin list ──────────────────────────────────────────────────────────────
# Keep this minimal. Add only what you actually use every day.
plugins=(
  romkatv/zsh-defer                           # async deferred sourcing (load first)
  Aloxaf/fzf-tab                              # fzf-powered tab completion (LOAD BEFORE fast-syntax-highlighting)
  zsh-users/zsh-autosuggestions               # fish-style inline suggestions
  zsh-users/zsh-history-substring-search      # fish-style ↑/↓ substring history search
  zdharma-continuum/fast-syntax-highlighting  # syntax highlighting (LOAD LAST)

  # Optional: uncomment if you use these tools
  # todie/asdf.plugin.zsh                  # asdf version manager integration
  # coreweave/dev-shell                    # coreweave-specific tooling
)

plugin load "${plugins[@]}"
unset plugins

# ── fzf-tab tuning ───────────────────────────────────────────────────────────
if (( $+functions[fzf-tab] )); then
  # Disable default completion menu in favor of fzf
  zstyle ':completion:*' menu no
  # Preview directories with eza, files with bat
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath 2>/dev/null || ls -1 $realpath'
  zstyle ':fzf-tab:complete:z:*' fzf-preview 'eza -1 --color=always --icons $realpath 2>/dev/null || ls -1 $realpath'
  zstyle ':fzf-tab:complete:(cat|bat|less|vim|nvim|code):*' fzf-preview 'bat --color=always --line-range=:200 $realpath 2>/dev/null'
  # Dim the descriptions, pop the matches
  zstyle ':completion:*:descriptions' format '[%d]'
  zstyle ':fzf-tab:*' fzf-flags --height=60% --border --color=fg:#a89bd6,bg:-1,hl:#ff2975,fg+:#ffffff,bg+:#160b3b,hl+:#ff2975,border:#2d1f4f,pointer:#ff2975,marker:#5af78e,spinner:#b026ff,header:#4a3f6b
  # Continuously trigger fzf for subcommand completions (e.g. git checkout <tab>)
  zstyle ':fzf-tab:*' continuous-trigger '/'
fi

# ── zsh-history-substring-search bindings ───────────────────────────────────
# Use ↑/↓ ONLY when the line is empty; otherwise our partial-line search wins.
# This gives us: empty line + ↑ → full fuzzy history, partial line + ↑ → prefix.
if (( $+functions[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^P'   history-substring-search-up
  bindkey '^N'   history-substring-search-down
  HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=#ff2975,fg=#0d0221,bold'
  HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=#ff5577,fg=#ffffff'
fi
