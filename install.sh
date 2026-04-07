#!/usr/bin/env bash
# install.sh — bootstrap todie/dotfiles
# Symlinks each dotfile into place. Safe to re-run (idempotent).

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%dT%H%M%S)"

BOLD="$(tput bold 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
NC="$(tput sgr0 2>/dev/null || printf '')"

info()      { printf '%s\n' "${BOLD}>${NC} $*"; }
ok()        { printf '%s\n' "${GREEN}✓${NC} $*"; }
warn()      { printf '%s\n' "${YELLOW}! $*${NC}"; }
err()       { printf '%s\n' "${RED}x $*${NC}" >&2; }

link() {
  local src="$1" dst="$2"

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    ok "Already linked: $dst"
    return
  fi

  if [[ -e "$dst" && ! -L "$dst" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/"
    warn "Backed up existing $dst → $BACKUP_DIR/"
  fi

  ln -sf "$src" "$dst"
  ok "Linked: $dst → $src"
}

# ── zsh ──────────────────────────────────────────────────────────────────────
link "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"

# ── claude code harness ─────────────────────────────────────────────────────
# PreToolUse Bash hooks and helper scripts. Each file is symlinked individually
# (not the whole directory) so unmanaged hooks in ~/.claude/hooks/ are
# preserved.
mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin"
link "$DOTFILES_DIR/claude/hooks/guard-dangerous-commands.sh" "$HOME/.claude/hooks/guard-dangerous-commands.sh"
link "$DOTFILES_DIR/claude/bin/claude-secret-test"            "$HOME/.local/bin/claude-secret-test"

# ── tmux ────────────────────────────────────────────────────────────────────
# N E O N   D R E A M S — main config + helper scripts referenced by the
# status bar (claude state, git branch) and keybindings (sessionizer, copy).
link "$DOTFILES_DIR/tmux/.tmux.conf"                "$HOME/.tmux.conf"
link "$DOTFILES_DIR/tmux/scripts/tmux-copy"         "$HOME/.local/bin/tmux-copy"
link "$DOTFILES_DIR/tmux/scripts/tmux-claude-state" "$HOME/.local/bin/tmux-claude-state"
link "$DOTFILES_DIR/tmux/scripts/tmux-git-branch"   "$HOME/.local/bin/tmux-git-branch"
link "$DOTFILES_DIR/tmux/scripts/tmux-sessionizer"  "$HOME/.local/bin/tmux-sessionizer"

# ── done ─────────────────────────────────────────────────────────────────────
info ""
info "Done. Restart your shell or: ${BOLD}exec zsh${NC}"
info ""
info "First launch will clone missing plugins automatically."
info "To update plugins later: ${BOLD}plugin update${NC}"
info ""
info "Verify the secret-leak guard hook: ${BOLD}claude-secret-test${NC}"
