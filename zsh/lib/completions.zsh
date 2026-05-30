# completions.zsh — tool completion registration.
#
# Strategy: generate each tool's zsh completion ONCE into the fpath dir
# ($HOME/.zsh/completions/_tool) and let compinit autoload it. Faster than
# `source <(tool completion zsh)` per startup (no subprocess) and avoids the
# interactive-mode errors that live-sourcing #compdef-tagged scripts produces.
# fpath is wired before compinit in .zshrc.
#
# After upgrading a tool, run `refresh-completions` to regenerate the cache.
#
# NOTE: some generators emit a stale #compdef binary name on line 1 (cortex
# still says `meshctl`, reveried/engram still says `reveried`). We rewrite the
# tag to match the real command so compinit registers it under the right name.

local compdir="$HOME/.zsh/completions"
[[ -d $compdir ]] || mkdir -p "$compdir"

# file → "generator cmd|||correct #compdef tag (optional, fixes stale tags)"
typeset -gA _COMPLETION_GEN=(
  _cortex 'cortex completions zsh|||cortex'
  _engram 'engram completions zsh|||engram'
  _rclone 'rclone completion zsh -'
  _sops   'sops completion zsh|||sops'
  _flyctl 'flyctl completion zsh'
  _rustup 'rustup completions zsh'
  _cargo  'rustup completions zsh cargo'
)

_gen_one() {
  local f=$1 spec=${_COMPLETION_GEN[$1]} compdir=$2
  local cmd=${spec%%|||*} tag=""
  [[ $spec == *'|||'* ]] && tag=${spec##*|||}
  local bin=${cmd%% *}
  command -v $bin &>/dev/null || return 1
  local out
  out=$(eval "$cmd" 2>/dev/null) || return 1
  [[ -n $out ]] || return 1
  # Rewrite a stale #compdef tag on the first line if a correction is given.
  if [[ -n $tag ]]; then
    local -a lines=("${(@f)out}")
    if [[ ${lines[1]} == '#compdef '* ]]; then
      lines[1]="#compdef $tag"          # rewrite stale tag (cortex→meshctl etc.)
    elif [[ ${lines[1]} != '#compdef'* ]]; then
      lines=("#compdef $tag" $lines)    # prepend missing tag (sops emits none)
    fi
    out=${(F)lines}
  fi
  print -r -- "$out" >| "$compdir/$f"
  [[ -s $compdir/$f ]] || { rm -f "$compdir/$f"; return 1; }
  return 0
}

# Regenerate every cached completion file. Use after tool upgrades.
refresh-completions() {
  local f
  for f in ${(k)_COMPLETION_GEN}; do
    if _gen_one "$f" "$compdir"; then print -r -- "regenerated $f"
    else print -r -- "skip $f"; fi
  done
  autoload -Uz compinit && compinit -u
}

# Startup: generate only missing files, reload compinit if any were added.
local f _added=0
for f in ${(k)_COMPLETION_GEN}; do
  [[ -s $compdir/$f ]] && continue
  _gen_one "$f" "$compdir" && _added=1
done
(( _added )) && { autoload -Uz compinit && compinit -u; }
unset f _added
