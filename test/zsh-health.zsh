#!/usr/bin/env zsh
# zsh-health.zsh — read-only health check for the dotfiles shell environment.
#
# Asserts the invariants this repo cares about are live in a configured shell:
# deduped PATH, resolved alias collisions, cached compinit, a working starship
# palette, etc. STRICTLY read-only — it never opens $EDITOR or mutates anything
# (learned the hard way: `starship config` opens the editor; we use
# `starship prompt` instead).
#
# Run it against your *installed* config (sources ~/.zshrc via -i):
#     zsh -i -c "source \${PWD}/test/zsh-health.zsh"
# or, from an already-interactive shell:
#     source test/zsh-health.zsh
#
# Exit/return code = number of failed checks (0 = all green).

emulate -L zsh
setopt no_unset 2>/dev/null

typeset -i _fail=0
typeset -g _RED=$'\e[31m' _GRN=$'\e[32m' _YLW=$'\e[33m' _NC=$'\e[0m'
[[ -t 1 ]] || { _RED= _GRN= _YLW= _NC= }

_ok()   { print -r -- "${_GRN}✓${_NC} $1"; }
_bad()  { print -r -- "${_RED}✗${_NC} $1"; (( _fail++ )); }
_skip() { print -r -- "${_YLW}–${_NC} $1 (skipped: $2)"; }

print -r -- "── dotfiles zsh health check ──────────────────────────────"

# PATH is deduplicated (typeset -gU path)
if [[ ${(t)path} == *unique* ]]; then _ok "path is unique-typed (typeset -U)"
else _bad "path is NOT unique-typed — duplicates will accumulate on reload"; fi
local -a _dupes=("${(@f)$(print -l $path | sort | uniq -d)}")
if (( ${#_dupes[@]} == 0 || ${#${_dupes:#}[@]} == 0 )); then _ok "no duplicate PATH entries"
else _bad "duplicate PATH entries: ${_dupes[*]}"; fi

# Editor configured
[[ -n ${EDITOR:-} ]] && _ok "EDITOR set: $EDITOR" || _bad "EDITOR is unset"

# No command-hiding aliases (policy: type the real command — see aliases.zsh)
local -a _hiders=(g gs gd gca k kg kd d dc dps h hi tf lg lzd k9 s3 j y f rgf dv)
local -a _present=()
local _a
for _a in $_hiders; do [[ -n ${aliases[$_a]:-} ]] && _present+=$_a; done
if (( ${#_present[@]} == 0 )); then _ok "no command-hiding aliases defined"
else _bad "command-hiding aliases present: ${_present[*]}"; fi

# compinit cache wired to the XDG path
if [[ -n ${ZCOMPDUMP:-} ]]; then _ok "ZCOMPDUMP set: ${ZCOMPDUMP}"
else _bad "ZCOMPDUMP unset — compinit daily-cache not active"; fi

# starship palette resolves (no "could not find color palette" warning)
if command -v starship >/dev/null 2>&1; then
  if { starship prompt >/dev/null; } 2>&1 | grep -qi 'could not find'; then
    _bad "starship palette unresolved (regenerate: theme set <name>)"
  else _ok "starship palette resolves"; fi
else _skip "starship palette" "starship not installed"; fi

# zedw host-Zed launcher (WSL only)
if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  command -v zedw >/dev/null 2>&1 && _ok "zedw on PATH" || _bad "zedw missing (run install.sh)"
else _skip "zedw" "not on WSL"; fi

# core plugins installed (cloned into ZPLUGINDIR). We check installation, not
# live loading: plugins load via zsh-defer at first prompt, so a non-prompt
# shell (zsh -i -c) wouldn't have the widgets yet — installation is the real
# invariant install.sh / first-run cares about.
local _pdir="${ZPLUGINDIR:-${DOTFILES_ZSH_CACHE:-$HOME/.cache/zsh}/plugins}"
local _p
for _p in zsh-autosuggestions fast-syntax-highlighting fzf-tab; do
  [[ -d $_pdir/$_p ]] && _ok "plugin installed: $_p" || _bad "plugin missing: $_p"
done
# bonus: if we're in a real interactive session that has reached a prompt, the
# widgets should also be live
if [[ -o interactive ]] && (( $+functions[_zsh_autosuggest_start] )); then
  _ok "zsh-autosuggestions live (widgets bound)"
fi

print -r -- "───────────────────────────────────────────────────────────"
if (( _fail == 0 )); then print -r -- "${_GRN}all checks passed${_NC}"
else print -r -- "${_RED}${_fail} check(s) failed${_NC}"; fi
return $_fail 2>/dev/null || exit $_fail
