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
  romkatv/zsh-defer                        # async deferred sourcing (load first)
  zsh-users/zsh-autosuggestions            # fish-style inline suggestions
  zdharma-continuum/fast-syntax-highlighting  # syntax highlighting

  # Optional: uncomment if you use these tools
  # Aloxaf/fzf-tab                         # fzf-powered tab completion
  # todie/asdf.plugin.zsh                  # asdf version manager integration
  # coreweave/dev-shell                    # coreweave-specific tooling
)

plugin load "${plugins[@]}"
unset plugins
