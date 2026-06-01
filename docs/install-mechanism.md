# Dotfiles install mechanism — research & recommendation

_Status: proposal for discussion. Researched 2026-05-31 (chezmoi docs via Context7)._

## The problem with the current approach

`install.sh` **symlinks** repo files into place (`~/.zshrc → repo/zsh/.zshrc`,
`~/.claude/hooks/* → repo/...`, `~/.tmux.conf`, `~/.local/bin/*`, …). That means
**the live config _is_ the repo working tree.** Consequences we've actually hit:

- **Git state mutates your running environment.** Checking out a branch changes
  your live shell instantly (we saw this — the new shell was running un-merged PR
  code because `~/.zshrc` points into the repo on whatever branch is checked out).
- A `git reset --hard`, `git stash`, `git clean`, or a broken WIP commit in the
  repo immediately breaks (or silently alters) your live shell/tmux/hooks.
- **No gate between "edit in repo" and "this is now my live config."** No preview,
  no staging, no atomic apply.
- **Secrets are bolted on.** `secrets.zsh` hand-rolls an `op read` cache and
  `render-zed-settings` manually runs `op inject` — re-implementing what modern
  managers do natively.

Symlinks aren't inherently wrong, but coupling git-state to live-state is the
"serious problem."

## State of the art (2026)

| Approach | Model | Decouples git state from live config? | Templating | Secrets | Verdict |
|---|---|---|---|---|---|
| **Symlink farms** — GNU Stow, dotbot, bare-git-repo (`git --work-tree=$HOME`) | symlink / in-place | **No** — checkout still mutates live files | no / minimal | no | Same problem we have |
| **chezmoi** | source → `apply` copies real files | **Yes** — repo is *source*, live files only change on `chezmoi apply` | Go templates | native (1Password, age/gpg) | **Recommended** |
| **Nix / home-manager** | declarative, atomic generations, rollback | Yes (most rigorous) | full Nix language | via sops-nix/agenix | Most powerful, heaviest; overkill unless going full-Nix |

## Recommendation: **chezmoi**

It targets exactly our pain:

1. **Explicit apply step decouples repo from live.** Source lives in
   `~/.local/share/chezmoi` (a normal git repo). `chezmoi apply` renders + copies
   files into `~`. `chezmoi diff` previews first. Switch branches / rebase / WIP
   freely — **nothing in `~` changes until you apply.** This is the direct fix.
2. **No symlinks by default** — deployed files are real copies, so when an app
   rewrites its own config (VS Code, starship `theme set`) it doesn't write back
   into your repo behind your back.
3. **Per-machine via templates** — replaces our `WSL_DISTRO_NAME` guards and
   `has` cascades: `{{ if eq .chezmoi.os "linux" }}…{{ end }}`. The
   `macos/defaults.sh` + WSL-only `zedw`/`win32yank` split becomes first-class.
4. **1Password native** — `{{ onepasswordRead "op://cloud/Anthropic API/credential" }}`
   injected at apply time, with **service-account-token mode** (we already set
   `OP_SERVICE_ACCOUNT_TOKEN`). This *replaces* `secrets.zsh` + `render-zed-settings`.
   Secrets never touch the repo.
5. **Encryption** (age/gpg) for any file that must be committed.
6. Single static Go binary; git-centric; signed-commit workflow unaffected.

### Honest tradeoffs / caveats

- **Mental-model change.** Editing config is no longer "edit the live symlink."
  It's `chezmoi edit --apply <file>` (or edit in `chezmoi cd`, then `chezmoi apply`).
  You lose live-edit immediacy; you gain a review gate. Mitigations: an alias
  `alias ca='chezmoi apply'`, or `chezmoi edit --watch`.
- **Migration is real, mostly mechanical work.** ~40 files need source-naming
  conventions: `dot_zshrc`, `private_` prefix for 0600 files, `.tmpl` for
  templated ones, `run_once_`/`run_onchange_` for the imperative bits of
  `install.sh` (starship `theme set` generation, completion generation). The
  `.chezmoiroot`/`.chezmoiignore` files control layout.
- chezmoi's own state lives in `~/.local/share/chezmoi`, separate from
  `~/projects/dotfiles` — we'd migrate the repo there (or point chezmoi at it).

## Lighter-weight alternative (if not adopting a tool)

Make `install.sh` **copy** instead of symlink. Copying decouples git-state from
live-state (the core fix) with near-zero new tooling. But you lose live-edit, must
re-run install to deploy, and gain none of chezmoi's templating/secrets/diff. It's
strictly a subset of chezmoi's value — only worth it to avoid learning a tool.

## Suggested path

1. Land the current cleanup PR (#9) first — don't mix a migration into it.
2. Spike chezmoi on a throwaway branch: `chezmoi init` against a copy, convert
   `zsh/` + `tmux/` + one secret, run `chezmoi diff` to confirm parity.
3. If it feels right, migrate incrementally (zsh → tmux → hooks → bin → secrets),
   keeping `install.sh` working until the cutover.
4. Replace `secrets.zsh`/`render-zed-settings` with `onepasswordRead` templates.

## References
- chezmoi docs: https://www.chezmoi.io  (concepts: source/target, `apply`, `diff`)
- 1Password functions: https://www.chezmoi.io/reference/templates/1password-functions/
- Real-world example (chezmoi + 1Password): github.com/twpayne/dotfiles
