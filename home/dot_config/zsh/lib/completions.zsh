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
# still says `meshctl`, engram still says `reveried`) or none at all (sops).
# We rewrite/prepend the tag to match the real command so compinit registers it
# under the right name; non-#compdef output is rejected outright.

local compdir="$HOME/.zsh/completions"
[[ -d $compdir ]] || mkdir -p "$compdir"

# file → "generator cmd|||correct #compdef tag (optional, fixes stale/missing tags)"
# Only installed tools that emit a REAL #compdef script belong here. _gen_one is
# hardened to reject any output that isn't a #compdef script, so an uninstalled
# tool or a generator that prints a usage stub simply gets skipped — but we keep
# the list to what's actually present to avoid dead entries.
# `terraform` and `vault` use `complete -C` (bashcompinit) and are wired in
# .zshrc / env.zsh respectively, not here.
typeset -gA _COMPLETION_GEN=(
  # generators that emit a correct #compdef tag on line 1 — no rewrite needed
  _gh                 'gh completion -s zsh'
  _kubectl            'kubectl completion zsh'
  _helm               'helm completion zsh'
  _k9s                'k9s completion zsh'
  _stern              'stern completion zsh'
  _kustomize          'kustomize completion zsh'
  _op                 'op completion zsh'
  _uv                 'uv generate-shell-completion zsh'
  _rclone             'rclone completion zsh -'
  _flyctl             'flyctl completion zsh'
  _rustup             'rustup completions zsh'
  _cargo              'rustup completions zsh cargo'
  # reverie mesh CLIs — emit real #compdef scripts under their own names
  _reveried           'reveried completions zsh'
  _reverie-bench      'reverie-bench completions zsh'
  _reverie-introspect 'reverie-introspect completions zsh'
  _reverie-tracee     'reverie-tracee completions zsh'
  # generators with a stale or missing tag — rewritten/prepended to the rhs
  _cortex             'cortex completions zsh|||cortex'   # emits stale #compdef meshctl
  _engram             'engram completions zsh|||engram'   # emits stale #compdef reveried
  _sops               'sops completion zsh|||sops'         # emits no #compdef tag at all
  _kubecolor          'kubecolor completion zsh|||kubecolor' # emits stale #compdef kubectl (it proxies kubectl)
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
  # Reject anything that isn't a real #compdef script (e.g. a tool whose
  # `completions zsh` prints a stub/usage line). Without this, a 15-byte stub
  # would be written and confuse compinit.
  [[ $out == '#compdef '* ]] || return 1
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
  autoload -Uz compinit && compinit -u -d "${ZCOMPDUMP:-${DOTFILES_ZSH_CACHE}/.zcompdump}"
}

# Startup: generate only missing files, reload compinit if any were added.
local f _added=0
for f in ${(k)_COMPLETION_GEN}; do
  [[ -s $compdir/$f ]] && continue
  _gen_one "$f" "$compdir" && _added=1
done
(( _added )) && { autoload -Uz compinit && compinit -u -d "${ZCOMPDUMP:-${DOTFILES_ZSH_CACHE}/.zcompdump}"; }
unset f _added
