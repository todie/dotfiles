# .zshenv — sourced for ALL shells (interactive, non-interactive, login, scripts)
# Keep this minimal and non-interactive safe: no prompts, no sourcing plugins,
# no commands that require a TTY.

export GPG_TTY=$TTY
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Cargo — available in non-interactive shells (scp, systemd user units, etc.)
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
