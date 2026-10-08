# macOS Onboarding Runbook

Personal fresh-Mac onboarding for **Europa** (M5 Max) and any Apple Silicon Mac.
Restores the full terminal environment + machine tooling from this chezmoi-managed
repo in a single `chezmoi apply`. Assumes macOS on Apple Silicon (Homebrew at
`/opt/homebrew`), operator access to the 1Password vault (for the age key +
service-account token), and that this repo is the single source of truth.

## Prerequisites

- An Apple Silicon Mac (Intel works — adjust the Homebrew path in Phase 1.2).
- Admin access (for Xcode CLT, Homebrew, and system defaults).
- 1Password app signed in (to retrieve the age key and the dotfiles
  service-account token).
- Network access.

## Phase 1 — System Foundations

### 1.1 Xcode Command Line Tools

Homebrew requires the CLT. Install, then click **Install** in the GUI prompt:

```bash
xcode-select --install
```

### 1.2 Homebrew

Clone-and-review (honors the "never pipe remote into bash" rule — download,
review, then run):

```bash
git clone https://github.com/Homebrew/install /tmp/brew-install
# review /tmp/brew-install/install.sh first
/bin/bash /tmp/brew-install/install.sh
eval "$(/opt/homebrew/bin/brew shellenv)"   # put brew on PATH for this session
```

On Apple Silicon brew lives at `/opt/homebrew`; on Intel it is `/usr/local` —
adjust the `brew shellenv` path accordingly.

The documented one-liner
(`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
is functionally identical; clone-and-review is the lead for safety.

### 1.3 chezmoi

```bash
brew install chezmoi
```

### 1.4 1Password — age key + service-account token

Three fresh-machine prerequisites (sources: `CLAUDE.md` "Bootstrap",
`home/.chezmoiignore` age section, `chezmoi.toml` `[age]`/`[onepassword]`,
`.chezmoidata.toml` `[secrets]`).

**Create the chezmoi config** — the repo-root `chezmoi.toml` is a reference copy
with a WSL-specific `sourceDir`; do NOT copy it verbatim. Create the config with
only the machine-independent sections (chezmoi defaults `sourceDir` to
`~/.local/share/chezmoi`):

```bash
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml <<'EOF'
encryption = "age"
umask = 0o022

[onepassword]
    mode = "service"

[age]
    identity = "~/.config/chezmoi/key.txt"
    recipient = "age1qyp6shdvaqgx9whayzz67zfme85wrvzc6qk6rrqsyj3estfdzvcs006ywp"

[data.secrets]
    apiKeys = true            # render op://cloud/* keys
    workstationKeys = true    # also render op://workstation-keys/* keys
EOF
```

Why: `encryption = "age"` + `[age]` lets chezmoi decrypt
`encrypted_private_dot_secrets.age`. `[onepassword] mode = "service"` lets
`onepasswordRead` resolve `op://` refs via the HTTPS API (no `op signin` needed;
the `op` CLI is NOT required for apply — it is installed later by the brew
bundle). `[data.secrets]` opts the machine into API-key rendering (default off in
`.chezmoidata.toml`); without it `secrets.env.tmpl` renders a no-op placeholder —
app keys are optional for a usable shell, but the machine will lack them until
you opt in.

**Restore the age identity** — retrieve the backed-up `key.txt` from 1Password,
then place it where the config above expects it:

```bash
cp <downloaded-key.txt> ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

Why: `home/encrypted_private_dot_secrets.age` decrypts to `~/.secrets`, which
holds `OP_SERVICE_ACCOUNT_TOKEN`. Without the age key, `chezmoi apply` cannot
decrypt it and errors.

**Retrieve the dotfiles service-account token** from 1Password and export it for
the apply:

```bash
export OP_SERVICE_ACCOUNT_TOKEN=ops_...
```

Why: `home/dot_config/zsh/private_secrets.env.tmpl` renders app keys from
1Password via `onepasswordRead` in service mode, which reads
`OP_SERVICE_ACCOUNT_TOKEN` from the apply-time environment.

## Phase 2 — Apply the Dotfiles

### 2.1 chezmoi init --apply

```bash
chezmoi init --apply todie
```

Clones the repo to `~/.local/share/chezmoi`, applies the `home/` tree to `~` as
real files (not symlinks), and runs every bootstrap script in order. Also
decrypts `encrypted_private_dot_secrets.age` → `~/.secrets` and renders
`~/.config/zsh/secrets.env` from 1Password.

What each run script does (sources: the script headers):

- **`run_once_before_20-zsh-plugins.sh.tmpl`** — pre-warms 5 zsh plugins
  (zsh-defer, fzf-tab, zsh-autosuggestions, zsh-history-substring-search,
  fast-syntax-highlighting) into the plugin cache so the first interactive shell
  is fast. Duplicates what `plugins.zsh`'s `plugin-load` self-heals at runtime.
- **`run_once_after_20-mise.sh.tmpl`** — installs the pinned mise binary
  (checksum-verified) then `mise install` materializes every pinned CLI + runtime
  from `~/.config/mise/config.toml`. Runs before `_25` and `_30` so mise-managed
  tools exist for them.
- **`run_once_after_25-k8s-tools.sh.tmpl`** — generates kubectl plugin-completion
  delegation shims (`kubectl_complete-<plugin>`) for cobra-based krew plugins so
  `kubectl <plugin> <TAB>` completes.
- **`run_once_after_30-zsh-completions.sh.tmpl`** — pre-warms per-tool zsh
  completion caches into `~/.zsh/completions` for installed tools, so the first
  shell doesn't pay the generation cost.
- **`run_onchange_after_10-starship-theme.sh.tmpl`** — generates the starship +
  tmux + fzf theme from the active palette by invoking the deployed `theme`
  binary. Defaults to synthwave-84 on first install; re-runs when any source
  theme toml changes.
- **`run_onchange_after_15-tmux-claude-reap.sh.tmpl`** — reaps stale
  `tmux-claude-state` / `tmux-claude-glanced` daemon instances and respawns the
  fresh version, so orphaned old copies don't pile up across redeploys.
- **`run_onchange_after_40-brew-bundle.sh.tmpl`** — runs
  `brew bundle --file ~/.Brewfile --no-upgrade` (macOS only). Installs every
  brew formula, cask, tap, and mas entry. Re-triggers when the Brewfile changes.

### 2.2 Two-pass secrets rendering (contingency)

If `OP_SERVICE_ACCOUNT_TOKEN` was NOT exported before the apply (or the
`[data.secrets]` opt-in flags were not set), `secrets.env.tmpl` renders a no-op
placeholder instead of aborting the apply. Fix:

```bash
source ~/.secrets      # now decrypted on disk; exports the token
chezmoi apply          # re-renders secrets.env with real keys
```

If the `[data.secrets]` flags were also missing, add them to
`~/.config/chezmoi/chezmoi.toml` (see Phase 1.4) before re-running `chezmoi
apply`.

## Phase 3 — macOS System Defaults

### 3.1 Run the defaults script

The defaults script lives at the repo-root `macos/` directory — NOT in the
chezmoi `home/` tree, so `chezmoi apply` does not run it. Invoke it manually:

```bash
bash ~/.local/share/chezmoi/macos/defaults.sh
```

What it sets (source: `macos/defaults.sh`):

- **Keyboard:** fast key repeat (`KeyRepeat` 2, `InitialKeyRepeat` 15), disable
  press-and-hold, full keyboard nav (`AppleKeyboardUIMode` 3).
- **Text input:** disable autocorrect, smart-quotes, smart-dashes, auto-periods,
  auto-capitalization.
- **Finder:** show all file extensions + hidden files, show path bar + status
  bar + POSIX path in title, search current folder by default, disable extension
  change warning, list view.
- **Dock:** autohide with no delay + scale effect, no recents, fast
  expose-animation.
- **No `.DS_Store`:** on network and USB volumes.
- **Screenshots:** save to `~/Screenshots` as PNG without shadows.
- **Save panels:** expanded, save to disk by default (not iCloud).
- **Window animations:** faster resize time.
- Restarts Finder / Dock / SystemUIServer at the end. Some changes need a
  logout/restart to fully take effect.

## Phase 4 — What Landed (Full-Machine Inventory)

One section per category. Sources named per section.

### 4.1 Shell + terminal configs (chezmoi-deployed)

Deployed as real files under `~` (sources: `home/` tree, `CLAUDE.md` Layout):

- **zsh** — `dot_zshrc` (entry point), `dot_zshenv` (non-interactive env),
  `dot_config/zsh/lib/*.zsh` (functions, env, plugins, completions, aliases,
  claude, secrets).
- **Ghostty** — `dot_config/ghostty/config` + themes (the terminal emulator).
- **herdr** — `dot_config/herdr/config.toml.tmpl` (the agentic terminal
  multiplexer).
- **tmux** — `dot_tmux.conf` + `dot_tmux.conf.d/claude.conf`.
- **starship** prompt (generated from palettes by `theme`).
- **atuin** shell history (`dot_config/private_atuin/private_config.toml`).
- **Zed** editor config (`dot_config/zed/`).
- **git** config (`dot_gitconfig.tmpl`, `dot_config/git/allowed_signers`,
  `dot_config/git/ignore`).
- **k9s** config (`dot_config/k9s/` — aliases, hotkeys, plugins, views, skins).
- `~/.local/bin/theme` recolors starship + tmux + fzf + (opt-in via
  `DOTFILES_THEME_WT=1`) Windows Terminal together.

### 4.2 mise machine toolchain

Source: `home/dot_config/mise/config.toml`. mise is the ONLY globally-activated
version manager (the machine layer per `docs/tooling-strategy.md`); `.zshrc` runs
`mise activate zsh` and nothing else. Pinned CLIs + runtimes:

- **k8s / infra CLIs:** helm, k9s, kustomize, stern, terraform, sops.
- **General CLIs:** gh, jq, lazygit, uv, direnv, rclone, flyctl, starship, gum,
  fzf.
- **Claude Developer Platform CLI (`ant`)** — `github:anthropics/anthropic-cli`
  (exe `ant`; SLSA-provenance + GitHub artifact-attestation verified).
- **Linear Release CLI (`linear-release`)** — `github:linear/linear-release`
  (SLSA-provenance verified; bridges CI/CD to Linear release management).
- **Shell / CLI-authoring stack:** argc, shfmt, shellcheck, bats.
- **Language runtimes:** node, go, deno (global defaults; per-repo overrides via
  proto).
- **Monorepo layer:** proto, moon, task (go-task), actionlint, linearctl, age.

Deliberate exclusions (managed elsewhere — do NOT add to mise):
- **kubectl** — `/usr/local/bin/kubectl` is a Docker-Desktop symlink,
  version-coupled to the bundled cluster.
- **bun** — `~/.local/bin/bun`, hard-referenced by the claude-hud statusline.
- **rust** — rustup/cargo at `~/.cargo`.
- **python** — system python3 + uv for project envs.
- **kubecolor, op** — provenance-sensitive; checksummed installer / cask.
- **engram / cortex / reverie-\*** — first-party builds via the deploy skills.

### 4.3 Shell / CLI core

Source: `home/dot_Brewfile` "Shell / CLI core" + "GNU/Linux CLI parity".

- chezmoi (this repo's own engine), rtk (CLI proxy to minimize LLM token
  consumption), atuin (shell history sync, Ctrl-R), bat (cat with syntax
  highlighting), coreutils (GNU userland), gnu-sed, eza (modern ls), fd (modern
  find), ripgrep, sd (intuitive find & replace), dust (modern du), zoxide
  (smarter cd), tmux, zellij (terminal workspace/multiplexer), tree, htop, btop,
  hexyl (hex viewer), hyperfine (CLI benchmarking), gron (make JSON greppable),
  dasel (JSON/YAML/TOML/XML/CSV query), miller (sed/awk/cut for CSV/name-indexed
  data), yq, yamllint, tokei (count code), pigz (parallel gzip), mas (Mac App
  Store CLI).
- **GNU/Linux CLI parity:** watch (procps), viddy (modern watch with diff
  highlighting + time-travel), flock (util-linux; the tmux claude-reap hook
  waits on it).

### 4.4 Core CLI / agent-config / local-MLX

Source: `home/dot_Brewfile` "Core CLI" section.

- rapid-mlx (fast local AI engine for Apple Silicon, OpenAI-compatible API),
  gita (manage multiple git repos), apm (dependency manager for AI agent
  configuration), herdr (agentic terminal multiplexer).

### 4.5 Git / dev toolchain

Source: `home/dot_Brewfile` "Git / dev toolchain".

- git-delta (syntax-highlighting pager for git diffs), difftastic (syntax-aware
  diff), lefthook (git hooks manager), pre-commit, cmake, cargo-binstall (binary
  install for rust crates), cargo-sweep (clean unused cargo build files), rustup,
  sccache (compiler cache), capnp (Cap'n Proto), mkcert (locally-trusted dev TLS
  certs), duckdb, postgresql@16, redis.

### 4.6 Containers / Docker

Source: `home/dot_Brewfile` "Containers / Docker" + casks.

- docker, docker-buildx, docker-compose, colima (container runtime without Docker
  Desktop), lazydocker, qemu.
- Cask: docker-desktop (owns `kubectl` at `/usr/local/bin/kubectl`).

### 4.7 k8s / infra

Source: `home/dot_Brewfile` "k8s / infra".

- kubecolor (colorized kubectl; `kubectl` is aliased to this), kubeconform
  (manifest validator), kyverno (policy management CLI), argocd, opentofu
  (terraform drop-in), openbao (vault drop-in), checkov (IaC misconfiguration
  scanner).
- Cask: tflint (terraform linter).
- Note: kubectl itself is NOT here — Docker Desktop owns it and the shell aliases
  `kubectl` → `kubecolor`.

### 4.8 Cloud / service CLIs + Networking

Source: `home/dot_Brewfile` "Cloud / service CLIs" + "Networking".

- **Cloud:** awscli, twilio.
- **Networking:** mosh, mtr (traceroute + ping), nmap, iperf3, socat, websocat
  (netcat for WebSockets), wget, httpie, croc (secure file transfer),
  ssh-copy-id, tailscale, wireshark (CLI build, tshark).

### 4.9 Security / supply chain / forensics

Source: `home/dot_Brewfile` "Security / supply chain / forensics".

- cosign (container signing), gitleaks (secret scanning in repos), grype (vuln
  scanner for images + filesystems), syft (SBOM generator), trivy (vuln scanner),
  semgrep, step (crypto/x509 swiss-army knife), ffuf (web fuzzer), binwalk
  (firmware/binary analysis), radare2 (reverse engineering), sleuthkit (forensic
  toolkit), testdisk (data recovery).

### 4.10 Media / images / docs

Source: `home/dot_Brewfile` "Media / images / docs".

- handbrake (video transcoder, CLI), gifsicle, jpegoptim, oxipng (PNG optimizer),
  svgo (SVG optimizer), vips (fast image processing), exiftool, media-info
  (tag/technical data for A/V files), mkvtoolnix (Matroska tools), sox (audio
  converter), yt-dlp, ocrmypdf (OCR layer for scanned PDFs), tesseract-lang
  (extra OCR languages), pandoc, typst (typesetting).

### 4.11 AI/LLM local stack + agent harnesses + voice

Source: `home/dot_Brewfile` "AI/LLM local stack" + "Agent harness CLIs" +
"Voice/ASR" + "Claude Code / agent desktop apps" + "Surprise picks".

- **AI/LLM local stack:** ollama, moshi-hook (bridges agents to Moshi mobile
  app; `rjyo/moshi` tap).
- **Agent harness CLIs (casks):** codex (OpenAI Codex terminal agent), claude-code
  (Anthropic terminal agent).
- **Voice / ASR (casks):** openwhispr (privacy-first voice-to-text), koe
  (zero-GUI voice input tool).
- **Claude Code / agent desktop apps (casks):** sessionwatcher (menu-bar monitor
  for AI coding-assistant usage + limits), claude-status-bar (menu-bar status
  indicator for Claude Code), clarc (desktop client for Claude Code),
  hermes-desktop (open-source desktop AI agent), codexia (GUI/toolkit for Codex
  CLI and Claude Code).
- **Kimi 3:** kimi-code (brew; AI coding agent for terminal), kimi (cask; Kimi 3
  desktop AI chat assistant).
- **Other:** humanbound (brew; adversarial security testing engine for AI agents),
  pixtuoid (brew; terminal pixel-art office for AI coding agents).

### 4.12 Disk + clipboard + window mgmt desktop apps

Source: `home/dot_Brewfile` casks + "Disk + dev-infra utils".

- **Casks:** neodisk (read-only disk-space visualiser), pastebot@2
  (clipboard-history workflow app), caffeine (keep-awake), ghostty (terminal
  emulator), obsidian, raycast, rectangle (window snapping), cate (infinite
  zoomable canvas with editor/terminal/browser panels), 1password-cli (the `op`
  CLI — installed here, not needed for the initial apply).
- **Brew:** dskditto (ultra-fast duplicate file finder TUI), droast (opinionated
  Dockerfile linter).

### 4.13 Nerd fonts

Source: `home/dot_Brewfile` "Casks — nerd fonts".

10 nerd-font casks: commit-mono, fira-code, geist-mono, hack, iosevka,
jetbrains-mono, meslo-lg, monaspice, sauce-code-pro, symbols-only.

### 4.14 Mac App Store apps

Source: `home/dot_Brewfile` "Mac App Store" (installed via the `mas` CLI).

1Password for Safari, Developer, Drone Flight Simulation, Final Cut Pro,
GarageBand, iMovie, Keynote, Loci, Logic Pro, Microsoft Excel, Microsoft OneNote,
Microsoft PowerPoint, Microsoft Word, Mudra Link, Numbers, OneDrive, Pages,
Pixelmator Pro, Slack, Telegram, WhatsApp.

`mas` requires being signed into the Mac App Store with the same Apple ID.

## Phase 5 — Verify

### 5.1 Shell health

```bash
zsh -i -c "source ~/.local/share/chezmoi/test/zsh-health.zsh"
```

Exit code = number of failed checks (0 = all green). Checks: deduped PATH,
resolved alias collisions, cached compinit, starship palette resolves, core
plugins installed, k8s completions registered. (Source: `test/zsh-health.zsh`
header.)

### 5.2 First terminal

Open a new Ghostty window. Confirm: plugins load (zsh-autosuggestions,
fast-syntax-highlighting, fzf-tab), starship prompt + theme appear, `theme list`
works.

### 5.3 Tooling sanity

```bash
mise ls                            # pinned CLIs/runtimes present
brew list --formula | wc -l        # formulae installed
```

### 5.4 Secrets rendered

Confirm `~/.config/zsh/secrets.env` is populated (check presence, never echo
values):

```bash
test -s ~/.config/zsh/secrets.env && echo "rendered" || echo "empty — see Phase 2.2"
```

### 5.5 Drift

```bash
chezmoi diff
```

Prints nothing when the live config matches the source.

## Phase 6 — Post-Onboarding

- **Theming:** `theme list` / `theme set <name>` (8 palettes; `theme next`
  cycles). WSL Windows-Terminal sync is opt-in (`DOTFILES_THEME_WT=1`, N/A on
  Mac).
- **Machine overrides:** `~/.zshrc-$USER` for host-specific config (sourced last,
  untracked by chezmoi).
- **Plugin updates:** `plugin update` / `plugin compile` / `plugin list`.
- **Candidate menu:** see `macos/utils.md` for deferred/skipped brew packages to
  wire in later.
- **Layering model:** see `docs/tooling-strategy.md` for the chezmoi/mise/proto/
  moon lane assignments.

---

Source of truth is this repo; re-run `chezmoi apply` after any edit. System
defaults via `macos/defaults.sh`. Candidate packages in `macos/utils.md`.
