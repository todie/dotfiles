# aliases.zsh — aliases and shell shims
#
# Policy: NO command-hiding shorthands. We do not alias `g`→git, `d`→docker,
# `gca`→git commit --amend, etc. Type the real command — it keeps shell history,
# scripts, and screen-shares readable, and never hides a non-trivial/destructive
# op behind two letters. Only these belong here:
#   • tool substitutions under the familiar name (ls→eza, cat→bat, top→btop)
#   • structural navigation (.., -)
#   • project cd-shortcuts and config-edit helpers
#
# CARVE-OUT — kubectl: the one deliberate exception. The de-facto-standard
# ohmyzsh kubectl alias set (`k`, `kgp`, `kaf`, …) is too entrenched in muscle
# memory and k8s docs/tutorials to forgo. It's namespaced under a single `k`
# prefix, the verbs stay legible (kgp = get pods, kdel = delete), and `kubectl`
# is itself aliased to kubecolor so the expansions inherit colorized output.
# Completion works natively: COMPLETE_ALIASES is unset, so `kgp <TAB>` expands
# to `kubectl get pods` and fzf-tab completes against _kubectl — no compdef.

alias sudo='/usr/bin/sudo'
alias grep='grep --color=auto'

# ── directory navigation ────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'                      # jump back to previous dir

# mkdir + cd in one step
mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

# ── ls / eza — modern ls under the familiar name ────────────────────────────
_eza_flags='--color=auto --color-scale --links --icons --git --group --changed'
if has eza; then
  alias ls='eza --color=auto --icons'
  alias l='eza -l --icons --git'
  alias ll='eza -l --icons --git --group'
  alias la='eza -la --icons --git --group'
  alias list="eza $_eza_flags --all -l --classify --group-directories-first --time-style=iso"
  alias tree='eza --tree --icons --level=3'
  alias tree2='eza --tree --icons --level=2'
  alias tree4='eza --tree --icons --level=4'
else
  alias ls='ls --color=always'
  alias l='ls -l'
  alias ll='ls -l'
  alias la='ls -la'
  alias list='ls --all -l --classify --group-directories-first --color=auto'
  alias tree='tree -C'
fi
unset _eza_flags

# ── cat → bat ───────────────────────────────────────────────────────────────
if has bat; then
  alias cat='bat --paging=never --style=plain'
  alias catp='bat'                     # cat-with-pager (full bat)
  alias catn='bat --style=numbers'     # cat with line numbers
fi

# ── btop → top (system monitor under the familiar name) ─────────────────────
has btop && alias top='btop'

# ── kubecolor → kubectl (colorized kubectl under the familiar name) ──────────
# Same tool-substitution pattern as ls→eza / cat→bat: kubecolor is a drop-in
# kubectl wrapper that colorizes output and falls back to plain kubectl for any
# command it doesn't recognize. It auto-disables color when piped/non-tty, so
# scripts and `kubectl … | grep` stay clean. Completion is registered under
# `kubecolor` in completions.zsh; the `kubectl` word keeps its own completion.
has kubecolor && alias kubectl='kubecolor'

# ── kubectl shortcuts (ohmyzsh kubectl plugin set) ───────────────────────────
# The full de-facto-standard alias set. See the kubectl CARVE-OUT in the header.
# Expansions reference `kubectl`, which the alias above redirects to kubecolor,
# so every shortcut inherits colorized output. Completion is automatic via zsh
# alias-expansion (COMPLETE_ALIASES unset) + fzf-tab — no compdef needed.
# Only gated on kubectl actually being installed.
if has kubectl || has kubecolor; then
  alias k='kubectl'
  alias kca='_kca(){ kubectl "$@" --all-namespaces;  unset -f _kca; }; _kca'
  alias kaf='kubectl apply -f'
  alias kapk='kubectl apply -k'
  alias keti='kubectl exec -t -i'

  # config / contexts
  alias kcuc='kubectl config use-context'
  alias kcsc='kubectl config set-context'
  alias kcdc='kubectl config delete-context'
  alias kccc='kubectl config current-context'
  alias kcgc='kubectl config get-contexts'
  alias kcn='kubectl config set-context --current --namespace'

  # delete
  alias kdel='kubectl delete'
  alias kdelf='kubectl delete -f'
  alias kdelk='kubectl delete -k'

  # events
  alias kge='kubectl get events --sort-by=".lastTimestamp"'
  alias kgew='kubectl get events --sort-by=".lastTimestamp" --watch'

  # pods
  alias kgp='kubectl get pods'
  alias kgpl='kgp -l'
  alias kgpn='kgp -n'
  alias kgpsl='kubectl get pods --show-labels'
  alias kgpa='kubectl get pods --all-namespaces'
  alias kgpw='kgp --watch'
  alias kgpwide='kgp -o wide'
  alias kep='kubectl edit pods'
  alias kdp='kubectl describe pods'
  alias kdelp='kubectl delete pods'
  alias kgpall='kubectl get pods --all-namespaces -o wide'

  # services
  alias kgs='kubectl get svc'
  alias kgsa='kubectl get svc --all-namespaces'
  alias kgsw='kgs --watch'
  alias kgswide='kgs -o wide'
  alias kes='kubectl edit svc'
  alias kds='kubectl describe svc'
  alias kdels='kubectl delete svc'

  # ingress
  alias kgi='kubectl get ingress'
  alias kgia='kubectl get ingress --all-namespaces'
  alias kei='kubectl edit ingress'
  alias kdi='kubectl describe ingress'
  alias kdeli='kubectl delete ingress'

  # namespaces
  alias kgns='kubectl get namespaces'
  alias kens='kubectl edit namespace'
  alias kdns='kubectl describe namespace'
  alias kdelns='kubectl delete namespace'

  # configmaps
  alias kgcm='kubectl get configmaps'
  alias kgcma='kubectl get configmaps --all-namespaces'
  alias kecm='kubectl edit configmap'
  alias kdcm='kubectl describe configmap'
  alias kdelcm='kubectl delete configmap'

  # secrets
  alias kgsec='kubectl get secret'
  alias kgseca='kubectl get secret --all-namespaces'
  alias kdsec='kubectl describe secret'
  alias kdelsec='kubectl delete secret'

  # deployments
  alias kgd='kubectl get deployment'
  alias kgda='kubectl get deployment --all-namespaces'
  alias kgdw='kgd --watch'
  alias kgdwide='kgd -o wide'
  alias ked='kubectl edit deployment'
  alias kdd='kubectl describe deployment'
  alias kdeld='kubectl delete deployment'
  alias ksd='kubectl scale deployment'
  alias krsd='kubectl rollout status deployment'
  alias krrd='kubectl rollout restart deployment'

  # replicasets / rollouts
  alias kgrs='kubectl get replicaset'
  alias kdrs='kubectl describe replicaset'
  alias kers='kubectl edit replicaset'
  alias krh='kubectl rollout history'
  alias kru='kubectl rollout undo'

  # statefulsets
  alias kgss='kubectl get statefulset'
  alias kgssa='kubectl get statefulset --all-namespaces'
  alias kgssw='kgss --watch'
  alias kgsswide='kgss -o wide'
  alias kess='kubectl edit statefulset'
  alias kdss='kubectl describe statefulset'
  alias kdelss='kubectl delete statefulset'
  alias ksss='kubectl scale statefulset'
  alias krsss='kubectl rollout status statefulset'
  alias krrss='kubectl rollout restart statefulset'

  # port-forward / get-all
  alias kpf='kubectl port-forward'
  alias kga='kubectl get all'
  alias kgaa='kubectl get all --all-namespaces'

  # logs
  alias kl='kubectl logs'
  alias kl1h='kubectl logs --since 1h'
  alias kl1m='kubectl logs --since 1m'
  alias kl1s='kubectl logs --since 1s'
  alias klf='kubectl logs -f'
  alias klf1h='kubectl logs --since 1h -f'
  alias klf1m='kubectl logs --since 1m -f'
  alias klf1s='kubectl logs --since 1s -f'

  # file copy
  alias kcp='kubectl cp'

  # nodes
  alias kgno='kubectl get nodes'
  alias kgnosl='kubectl get nodes --show-labels'
  alias keno='kubectl edit node'
  alias kdno='kubectl describe node'
  alias kdelno='kubectl delete node'

  # persistent volume claims
  alias kgpvc='kubectl get pvc'
  alias kgpvca='kubectl get pvc --all-namespaces'
  alias kgpvcw='kgpvc --watch'
  alias kepvc='kubectl edit pvc'
  alias kdpvc='kubectl describe pvc'
  alias kdelpvc='kubectl delete pvc'

  # service accounts
  alias kdsa='kubectl describe sa'
  alias kdelsa='kubectl delete sa'

  # daemonsets
  alias kgds='kubectl get daemonset'
  alias kgdsa='kubectl get daemonset --all-namespaces'
  alias kgdsw='kgds --watch'
  alias keds='kubectl edit daemonset'
  alias kdds='kubectl describe daemonset'
  alias kdelds='kubectl delete daemonset'

  # cronjobs
  alias kgcj='kubectl get cronjob'
  alias kecj='kubectl edit cronjob'
  alias kdcj='kubectl describe cronjob'
  alias kdelcj='kubectl delete cronjob'

  # jobs
  alias kgj='kubectl get job'
  alias kej='kubectl edit job'
  alias kdj='kubectl describe job'
  alias kdelj='kubectl delete job'

  # kres <resource>: roll a resource by patching a restart-timestamp annotation
  kres() { kubectl set env "$1" "$2" REFRESHED_AT="$(date +%Y%m%dT%H%M%S)"; }

  # kj: pipe kubectl JSON output through jq (kjx/ky from the upstream plugin need
  # fx/yh, which aren't installed here, so they're omitted — no dead helpers).
  has jq && kj() { kubectl "$@" -o json | jq; }
fi

# ── zoxide (smart cd) ───────────────────────────────────────────────────────
# `z foo` jumps to the most-frecent dir matching foo; `zi` is interactive.
# Provided by `zoxide init` (env.zsh), not aliased here.

# ── clipboard (WSL2-friendly, matches tmux-copy script) ─────────────────────
if has clip.exe || has win32yank.exe; then
  if has win32yank.exe; then
    alias pbcopy='win32yank.exe -i --crlf'
    alias pbpaste='win32yank.exe -o'
  else
    alias pbcopy='clip.exe'
  fi
fi

# ── Zed on the Windows host (WSL) ────────────────────────────────────────────
# `zedw` opens paths in the Windows-host Zed via Zed's --wsl remoting. It's a
# real binary (bin/zedw, symlinked to ~/.local/bin by install.sh) — NOT an alias
# — so it also works as $EDITOR: `export EDITOR="zedw --wait"`. See `zedw` header.

# ── quick config edits ──────────────────────────────────────────────────────
alias zshrc='${EDITOR:-vim} ~/projects/dotfiles/zsh/.zshrc'
alias tmuxrc='${EDITOR:-vim} ~/projects/dotfiles/tmux/.tmux.conf'
alias starrc='${EDITOR:-vim} ~/projects/dotfiles/starship/base.toml'
alias reload='exec zsh'

# ── cd shortcuts to common projects (uses cdable_vars) ──────────────────────
export dotfiles="${HOME}/projects/dotfiles"
export pact="${HOME}/projects/pact"
export reach="${HOME}/projects/reach"
export reverie="${HOME}/projects/reverie"
