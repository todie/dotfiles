## secrets.zsh — load API tokens from 1Password into env vars.
##
## Tokens live in op://cloud/<item>/credential. We read them lazily so shell
## startup stays snappy — call `secrets-load` (or set DOTFILES_AUTO_SECRETS=1)
## to populate. Results are cached in $XDG_CACHE_HOME/zsh-secrets.env for the
## current day to avoid hitting `op` on every shell start.

has op || return 0

_SECRETS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-secrets.env"
_SECRETS_TTL_HOURS=12

# Map env var name → 1Password reference.
## Note: parentheses and other special chars are invalid in op:// references,
## so items with such names are looked up by UUID.
typeset -gA _SECRETS_MAP=(
  [GITHUB_PERSONAL_ACCESS_TOKEN]="op://cloud/if4isjyeictbjj5rqijf3bcgdm/credential"
  [GITHUB_CEREBRAL_TOKEN]="op://cloud/w2qcdty2ei5oc2sudwfe74yiwe/credential"
  [LINEAR_API_KEY]="op://cloud/Linear API/credential"
  [ANTHROPIC_API_KEY]="op://cloud/Anthropic API/credential"
  [OPENROUTER_API_KEY]="op://cloud/OpenRouter API/credential"
)

secrets-load() {
  local force="${1:-}"
  local cache_age_hours

  # Use cache if fresh and not forcing.
  if [[ -r "$_SECRETS_CACHE" && "$force" != "--force" ]]; then
    cache_age_hours=$(( ($(date +%s) - $(stat -f %m "$_SECRETS_CACHE")) / 3600 ))
    if (( cache_age_hours < _SECRETS_TTL_HOURS )); then
      source "$_SECRETS_CACHE"
      return 0
    fi
  fi

  # Refresh cache from 1Password.
  print -P "%F{cyan}▸%f loading secrets from 1Password..."
  : > "$_SECRETS_CACHE"
  chmod 600 "$_SECRETS_CACHE"

  local var ref value
  for var ref in "${(@kv)_SECRETS_MAP}"; do
    value="$(op read "$ref" 2>/dev/null)" || {
      print -P "%F{yellow}⚠%f  $var: failed to read $ref"
      continue
    }
    print "export $var=${(q)value}" >> "$_SECRETS_CACHE"
  done

  source "$_SECRETS_CACHE"
}

secrets-clear() {
  rm -f "$_SECRETS_CACHE"
  print -P "%F{green}✓%f secrets cache cleared"
}

secrets-list() {
  print -P "%F{cyan}configured secrets:%f"
  for var ref in "${(@kv)_SECRETS_MAP}"; do
    print "  $var → $ref"
  done
}

# Auto-load if requested. Set in ~/.zshrc-${USER} for opt-in behavior.
[[ "${DOTFILES_AUTO_SECRETS:-0}" == "1" ]] && secrets-load
