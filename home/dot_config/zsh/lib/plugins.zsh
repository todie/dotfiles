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
    # Load SYNCHRONOUSLY. zsh-defer's idle-flush (a zle -F fd-handler) proved
    # unreliable in this env: the deferred plugin inits never ran, so fzf-tab
    # never rebound TAB (stuck on the default expand-or-complete) and
    # zsh-autosuggestions / fast-syntax-highlighting never started — i.e.
    # completions AND inline suggestions silently dead. Verified: all three load
    # and bind correctly when sourced synchronously after compinit. The ~tens of
    # ms startup cost is the right trade for an interactive shell that works.
    . "$initfile"
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
# fzf-tab needs the `fzf` BINARY, not just the plugin function. If fzf is absent,
# engaging fzf-tab AND setting `menu no` leaves TAB dead — the picker can't run
# and the normal menu is disabled. So only engage fzf-tab when fzf is actually
# installed; otherwise disable it and restore a normal navigable menu so TAB
# still completes. (Requires synchronous plugin load above, so fzf-tab is already
# loaded when this guard runs.)
if (( $+functions[fzf-tab-complete] )) && command -v fzf >/dev/null 2>&1; then
  # Disable default completion menu in favor of fzf
  zstyle ':completion:*' menu no
  # Preview directories with eza, files with bat
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath 2>/dev/null || ls -1 $realpath'
  zstyle ':fzf-tab:complete:z:*' fzf-preview 'eza -1 --color=always --icons $realpath 2>/dev/null || ls -1 $realpath'
  zstyle ':fzf-tab:complete:(cat|bat|less|vim|nvim|code):*' fzf-preview 'bat --color=always --line-range=:200 $realpath 2>/dev/null'
  # Dim the descriptions, pop the matches
  zstyle ':completion:*:descriptions' format '[%d]'
  # fzf-tab colors from the active theme (THEME_FZFTAB_COLORS, set in env.zsh).
  zstyle ':fzf-tab:*' fzf-flags --height=60% --border --color="${THEME_FZFTAB_COLORS:-hl:cyan,hl+:cyan}"
  # Continuously trigger fzf for subcommand completions (e.g. git checkout <tab>)
  zstyle ':fzf-tab:*' continuous-trigger '/'
elif (( $+functions[disable-fzf-tab] )); then
  # fzf-tab loaded but the fzf binary is missing → un-hijack TAB and give back a
  # normal navigable menu, so completion still works instead of dying silently.
  disable-fzf-tab
  zstyle ':completion:*' menu select
fi

# ── zsh-autosuggestions color ───────────────────────────────────────────────
# The inline-suggestion highlight. The plugin's built-in default is fg=8 (ANSI
# bright-black), which on a dark theme renders ≈ the background → suggestions are
# present but INVISIBLE (the recurring "autocomplete borked after theme change").
# Drive it from the active palette (THEME_AUTOSUGGEST, set in theme.zsh) with a
# visible 256-colour grey fallback for before any theme has been generated.
# Set BEFORE the deferred plugin init reads it (sourcing runs pre-first-precmd).
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="${THEME_AUTOSUGGEST:-fg=242}"

# ── zsh-history-substring-search bindings ───────────────────────────────────
# These OVERRIDE the up-line-or-beginning-search bindings from options.zsh when
# the plugin is present: ↑/↓/^P/^N do substring history search (type any text,
# ↑ cycles matches containing it). options.zsh's prefix-search bindings remain
# the fallback if the plugin failed to load.
if (( $+functions[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^P'   history-substring-search-up
  bindkey '^N'   history-substring-search-down
  # highlight colors from the active theme (THEME_HSS_*, set in env.zsh)
  HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND="${THEME_HSS_FOUND:-bg=cyan,fg=black,bold}"
  HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND="${THEME_HSS_NOTFOUND:-bg=red,fg=white}"
fi

# ── Transient prompt ──────────────────────────────────────────────────────────
# Collapse the spent prompt to a bare ❯ once a command runs, keeping scrollback
# clean. starship has NO native zsh transience (verified against v1.25.1 — its
# `init zsh` defines no enable_transience), so this wraps accept-line ourselves.
# It MUST be the outermost accept-line, so the binding is deferred onto the same
# zsh-defer queue as fast-syntax-highlighting / zsh-autosuggestions (which also
# touch the line editor) — guaranteeing it runs after them. If it ever fights the
# highlighter or suggestions, delete this block; the airy prompt stands alone.
# On accept: collapse the SPENT line to a bare ❯, then run the command. starship
# sets PROMPT once to a `$(starship …)` string and never re-assigns it (its precmd
# only captures $?/duration/jobs), so we must cache that string and RESTORE it on
# the next precmd — otherwise the bare ❯ would stick for the rest of the session.
_transient_prompt() {
  PROMPT='%F{13}❯%f '
  RPROMPT=''
  zle .reset-prompt
  zle .accept-line
}
_restore_prompt() { PROMPT=$_STARSHIP_PROMPT; RPROMPT=$_STARSHIP_RPROMPT }
_install_transient_prompt() {
  _STARSHIP_PROMPT=$PROMPT          # the live `$(starship prompt …)` string
  _STARSHIP_RPROMPT=$RPROMPT
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _restore_prompt
  zle -N accept-line _transient_prompt
}
(( $+functions[zsh-defer] )) && zsh-defer _install_transient_prompt || _install_transient_prompt
