## secrets.zsh — load API tokens from 1Password into env vars.
##
## Under the chezmoi copy model the op:// references are resolved ONCE at
## `chezmoi apply` time (via onepasswordRead in secrets.env.tmpl) and written to
## ~/.config/zsh/secrets.env (0600). This kills the per-shell `op read` latency
## and the daily-cache machinery that the symlink setup used. We simply source
## the rendered file here if it exists.
##
## Bootstrap: ~/.secrets is OPERATOR-MANAGED (NOT chezmoi-rendered — it's in
## .chezmoiignore) and holds OP_SERVICE_ACCOUNT_TOKEN so the op-mcp wrapper and
## any interactive `op` work headlessly. It is the env source that [onepassword]
## mode="service" reads during `chezmoi apply` to resolve the op:// refs in
## secrets.env.tmpl. Provision it by hand once on a fresh machine (the
## irreducible bootstrap step — the token can't render the file that holds it).
## If the token is absent at apply time, secrets.env.tmpl renders a no-op
## placeholder instead of aborting the apply; re-run apply once it's present.

# Bootstrap token for headless `op` (op-mcp wrapper sources this too — single
# source of truth). Loaded regardless of whether `op` is installed.
[[ -r "$HOME/.secrets" ]] && { set -a; source "$HOME/.secrets"; set +a; }

# Apply-time-rendered secrets (export VAR=... lines). Present iff `chezmoi apply`
# resolved the op:// refs. Sourced silently; absence is non-fatal.
[[ -r "$HOME/.config/zsh/secrets.env" ]] && source "$HOME/.config/zsh/secrets.env"

## Back-compat shims for the old runtime interface. Secrets are now resolved at
## apply time and sourced above on every shell, so loading is eager and these
## are effectively no-ops. Kept so existing muscle memory / scripts / the
## DOTFILES_AUTO_SECRETS=1 opt-in don't error after the migration.
secrets-load() {
  [[ -r "$HOME/.config/zsh/secrets.env" ]] && source "$HOME/.config/zsh/secrets.env"
  print -P "%F{green}✓%f secrets sourced from ~/.config/zsh/secrets.env (rendered at apply time)"
}
secrets-clear() {
  print -P "%F{yellow}⚠%f secrets are apply-time-rendered now; run \`chezmoi apply\` to re-render ~/.config/zsh/secrets.env"
}

## render-zed-settings — resolve op:// refs in settings.json.tpl into the
## live settings.json. Run after editing the template, or wire to a hook.
## (Retained as an opt-in helper; chezmoi may take this over via a private_
## settings.json.tmpl in a later pass.)
render-zed-settings() {
  has op || { print -P "%F{yellow}⚠%f op not installed"; return 1; }
  local tpl="$HOME/.config/zed/settings.json.tpl"
  local out="$HOME/.config/zed/settings.json"
  [[ -r "$tpl" ]] || { print -P "%F{yellow}⚠%f no template at $tpl"; return 1; }
  op inject -i "$tpl" -o "$out" -f && \
    print -P "%F{green}✓%f rendered $out from template"
}
