# org.zsh — cerebral.work team defaults.
# Org-wide environment that is safe to share. Personal values go in
# ~/.zshrc-$USER; secrets go in ~/.config/zsh/secrets.env (see secrets.zsh).

# OpenBao (secrets store) — reachable via the tailnet LB. If this hostname
# doesn't resolve, you're not on the tailnet.
export BAO_ADDR=http://bao.tail769bd2.ts.net

# Cygnus kubeconfig convention: single-context file at ~/.kube/cygnus pointing
# directly at the API VIP (via the tailnet subnet route). Minted during
# onboarding; wired up only if present, never overriding an explicit setting.
[[ -z ${KUBECONFIG:-} && -f $HOME/.kube/cygnus ]] && export KUBECONFIG="$HOME/.kube/cygnus"

# Bastion shell — per-user account provisioned during onboarding.
# (Tailscale SSH is the live path; the host key install is a dormant fallback.)
alias bastion='ssh bastion-dev'

# ── workspace topology (~/projects & ~/projects/domain) ──────────────────────
# Canonical 3-level layout:
#   Repos:     ~/projects/<team>/<category>/<repo>
#   Worktrees: ~/projects/<team>/<category>/.worktrees/<repo>/<branch>
#   Control:   ~/projects/domain (cerebral-work/projects) + domain/{core,kernel,schedule,runtime}
export PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
export PROJECTS_DOMAIN="${PROJECTS_DOMAIN:-$PROJECTS_ROOT/domain}"
export PROJECTS_TOPOLOGY_MANIFEST="${PROJECTS_TOPOLOGY_MANIFEST:-$PROJECTS_DOMAIN/topology.yaml}"
export PROJECTS_PROJECTFILE="${PROJECTS_PROJECTFILE:-$PROJECTS_DOMAIN/projectfile.yaml}"

# domain — jump to ~/projects/domain (or a subpath inside it).
domain() {
  if (( $# == 0 )); then
    cd -- "${PROJECTS_DOMAIN:-$HOME/projects/domain}"
  else
    cd -- "${PROJECTS_DOMAIN:-$HOME/projects/domain}/$1"
  fi
}

# topology — shell wrapper around topology-ctl that adds `topology cd <repo>`.
topology() {
  if [[ "${1:-}" == "cd" ]]; then
    shift
    proj "$@"
    return $?
  fi
  command topology-ctl "$@"
}

# proj — jump to a repository in ~/projects/<team>/<category>/<repo>.
#   proj                 interactive fzf picker across mapped repositories
#   proj <repo|path>     resolve via topology-ctl and cd directly
proj() {
  if (( $# == 0 )); then
    if [[ -t 1 ]] && has fzf && has topology-ctl; then
      local rel
      rel=$(topology-ctl list 2>/dev/null | fzf \
        --prompt='project ▸ ' \
        --preview "git -C \"$PROJECTS_ROOT/{}\" status -sb 2>/dev/null; echo; git -C \"$PROJECTS_ROOT/{}\" log -n 5 --oneline 2>/dev/null || ls -la \"$PROJECTS_ROOT/{}\"")
      [[ -n "$rel" ]] && cd -- "$PROJECTS_ROOT/$rel"
      return 0
    fi
    cd -- "$PROJECTS_ROOT"
    return $?
  fi

  local target
  if has topology-ctl && target=$(topology-ctl path "$1" 2>/dev/null); then
    cd -- "$target"
  elif [[ -d "$PROJECTS_ROOT/$1" ]]; then
    cd -- "$PROJECTS_ROOT/$1"
  else
    perror "proj: unknown repository or path '$1'"
    return 1
  fi
}

# pwt — create or enter a canonical git worktree under:
#   ~/projects/<team>/<category>/.worktrees/<repo>/<branch>
pwt() {
  if (( $# < 2 )); then
    perror "usage: pwt <repo> <branch> [base-ref]"
    return 1
  fi
  local repo="$1" branch="$2" base="${3:-main}"
  local repo_path wt_path
  repo_path=$(topology-ctl path "$repo") || return 1
  wt_path=$(topology-ctl worktree-path "$repo" "$branch") || return 1

  if [[ -d "$wt_path" ]]; then
    cd -- "$wt_path"
    return 0
  fi

  mkdir -p -- "$(dirname "$wt_path")"
  if git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo_path" worktree add "$wt_path" "$branch" || return 1
  else
    git -C "$repo_path" worktree add -b "$branch" "$wt_path" "$base" || return 1
  fi
  cd -- "$wt_path"
}

# pbut — enter a repository in ~/projects/<team>/<category>/<repo>, ensure its
# GitButler workspace (`gitbutler/workspace`) is initialized, and optionally
# create or apply a virtual branch in place.
pbut() {
  if (( $# < 1 )); then
    perror "usage: pbut <repo> [branch]"
    return 1
  fi
  if ! has but; then
    perror "pbut: GitButler CLI ('but') is not installed"
    return 1
  fi
  local repo="$1" branch="${2:-}"
  local repo_path
  repo_path=$(topology-ctl path "$repo") || return 1
  cd -- "$repo_path" || return 1

  if [[ "$(git symbolic-ref --short HEAD 2>/dev/null)" != "gitbutler/workspace" ]]; then
    but setup || return 1
  fi

  if [[ -n "$branch" ]]; then
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      but apply "$branch"
    else
      but branch new "$branch"
    fi
  else
    but status
  fi
}

if (( $+functions[compdef] )); then
  _proj() {
    local -a repos
    if has topology-ctl; then
      repos=(${(f)"$(topology-ctl list 2>/dev/null)"})
      repos+=(${repos:t})
    fi
    _describe 'project' repos
  }
  _topology_ctl() {
    local -a subcmds
    subcmds=(
      'status:summary of teams, categories, repos, and worktrees'
      'validate:verify manifest and disk alignment'
      'audit:check for unmapped dirs, symlinks, and broken worktrees'
      'migrate:relocate legacy <org>/<repo> checkouts to canonical paths'
      'sync:reconcile topology.yaml, TSV manifests, and team docs'
      'repair-worktrees:repair git worktree pointers across all repos'
      'gen-docs:regenerate README.md and teams/*.md'
      'list:list canonical <team>/<category>/<repo> paths'
      'path:resolve repository name to canonical path'
      'clone:clone cataloged repository into its canonical <team>/<category>/<repo> path'
      'worktree-path:print canonical .worktrees/<repo>/<branch> path'
      'but:run GitButler CLI against a cataloged repository'
      'bootstrap:seed ~/projects skeleton and ~/projects/domain repo'
      'cd:jump to repository directory'
    )
    if (( CURRENT == 2 )); then
      _describe 'topology command' subcmds
    elif [[ "${words[2]}" == (path|cd|clone|worktree-path|wt-path|but) ]]; then
      _proj
    fi
  }
  compdef _proj proj pwt pbut 2>/dev/null
  compdef _topology_ctl topology-ctl topology 2>/dev/null
fi


