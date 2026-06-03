<!--
Source: awesome-shell "Shell Script Development" section
  https://github.com/alebcay/awesome-shell#shell-script-development
Method: 41 web-verified research agents (one per tool) + a synthesis pass, run
  2026-06-03 via the awesome-shell-research workflow.
Lens: building a BEST-PRACTICES bash CLI-authoring stack (not just helper scripts)
  for this chezmoi + mise + gum environment with a shellcheck/zsh -n CI gate.
-->

# Best-Practices Bash-CLI Authoring Stack (from awesome-shell "Shell Script Development")

## 1. Overview

A real bash CLI — multi-flag, subcommand-capable, self-documenting — needs eight layers: **(a) arg-parsing + auto-help + subcommand dispatch**, **(b) scaffolding**, **(c) testing/mocking**, **(d) interactive UX**, **(e) quality gates** (format/lint/LSP), **(f) logging**, **(g) packaging/distribution**, **(h) templating**. awesome-shell fills (a), (c), and (e) *very well* and (h) adequately; (d) is solved off-list by gum (already adopted); **(f) and (g) have no healthy tool in the set** — both are gaps you fill with idioms + mise. The single most consequential pick is layer (a): the right answer for *this* mise-pinned, bash-purist environment is **argc** — a Rust single-binary, mise-installable, comment-driven parser — not the helper-script verdicts in the source JSON, which uniformly said "skip arg-parsing, getopts is fine." That lens was wrong for the authoring goal and I've re-judged everything against the new one.

## 2. The recommended stack (centrepiece)

| Layer | Pick | Runner-up | Why | Install |
|---|---|---|---|---|
| **(a) arg-parse / subcommands / help** | **argc** | bashly · getoptions | Rust single binary, **mise-installable**, defines CLI with inline `# @cmd`/`# @option`/`# @arg` comment tags above functions — no separate spec file, no regen-to-disk build step, auto `--help` + completions. Best fit for a mise/bash-purist tree. | `mise use -g argc` |
| **(b) scaffolding** | **bashew** | bashly `init` | Only *actively-maintained* (2026) dedicated scaffolder in the set; `bashew script`/`bashew project` emit a flag-parsed skeleton + CI + test stubs. Strip its IO color helpers (gum owns that). | `basher install pforret/bashew` |
| **(c) testing + mocking** | **bats-core** | shellspec | De-facto bash test framework, TAP, mise-pinnable, drops into existing CI as a 3rd step. Reach for shellspec instead when you need **command mocking** (mock `tmux`/`ps`/`kill`) or coverage. | `mise use -g bats` |
| **(d) interactive UX** | **gum** (have it) | — | Runtime layer: `gum input/confirm/choose/spin/style`. Orthogonal to argc (build-time parsing). Slot gum *inside* command bodies for prompts/spinners. | already at 0.17.0 |
| **(e) quality gates** | **shfmt + shellcheck** (+ bash-language-server) | — | shfmt = the missing formatter (`gofmt` for bash); shellcheck = lint (already your CI gate, just not local); bash-LSP backs your "LSP-first" mandate with goto-def/hover. | `mise use -g shfmt shellcheck` |
| **(f) logging** | **GAP — hand-rolled `log()` / `logger(1)`** | — | No healthy tool: lumberjack dead-2016, bash-modules is LGPL-copyleft. Use a 5-line leveled `log()` printf helper, or `logger(1)`/`systemd-cat` for journald. | n/a (idiom) |
| **(g) packaging / distribution** | **GAP — mise + single-file codegen output** | — | No healthy tool: shellfire `fatten`/rerun archives are stale. argc/bashly already emit a single standalone script; distribute via mise/chezmoi. | n/a (mise + chezmoi) |
| **(h) templating / config-gen** | **esh** | mo | ERB-style POSIX-shell single file, supports includes, distro-packaged. Use only for config generation *outside* chezmoi (chezmoi `.tmpl` already covers dotfiles). | `apk add esh` / vendor pinned-sha |

## 3. Re-judged by category (CLI-authoring lens, NOT the old helper lens)

### arg-parsing
| Tool | What | Health | Fit |
|---|---|---|---|
| bashly | YAML-driven bash CLI generator | active | **core** (runner-up to argc; Ruby/Docker + regen step is the cost) |
| getoptions | Pure-POSIX parser w/ generator mode | stale | **optional** (zero-dep minimalist; `gengetoptions` emits standalone parser) |
| optparse | getopts wrapper, single-line opts | stale | skip (bash-only, dormant, sed/temp-file) |
| dispatch | ~50-line POSIX argv router | archived | skip (11-yr-dead) |
| getopts.fish | Fish options parser | active | skip (fish-only) |

### framework-scaffolding
| Tool | What | Health | Fit |
|---|---|---|---|
| bashew | Active bash script/project scaffolder | active | **core** (the one live scaffolder) |
| sub | git-style subcommand dispatcher convention | stale | optional (good *idea*; clone-a-tree fights chezmoi — prefer argc) |
| shellfire | Namespaced module libs + `fatten` packager | stale | skip (7-yr cold, submodule-per-module) |
| rerun | Folder-of-scripts → module:command CLI | stale | skip (8-yr dead) |
| bashmanager | tasks.d dispatcher framework | stale | skip (2016) |
| bashwithnails | Module system + weak OOP | stale | skip (hobby, dormant) |
| rebash | Bash import system + try/catch + doctests | stale | skip (AUR-only, 2022) |

### testing
| Tool | What | Health | Fit |
|---|---|---|---|
| bats-core | TAP bash test framework | active | **core** (the pick) |
| shellspec | BDD shell tests w/ mocking + coverage | active | **core** (when you need mocking) |
| shunit2 | xUnit-style sh/bash/zsh | active | optional (active but tag-stale; bats stronger for new setup) |
| critic.sh | Single-file tests + built-in coverage | stale | optional (only if built-in coverage is decisive) |
| ts | Pure-sh runner, per-test sandboxes | stale | skip (2020, POSIX-centric) |
| assert.sh | 3-primitive assertion lib | stale | skip (11-yr dormant) |
| shpec | BDD w/ command stubbing | stale | skip (2019, no mise) |
| urchin | Exit-status-only runner | stale | skip (repo 404, npm deprecated) |
| zunit | zsh-only BATS-style | stale | skip (2020, needs revolver) |
| Fishtape | Fish TAP runner | stale | skip (fish-only) |

### linting-formatting
| Tool | What | Health | Fit |
|---|---|---|---|
| shfmt | Go bash formatter (gofmt-for-shell) | active | **core** (fills the missing format layer) |
| ShellCheck | Static bash linter, SC#### codes | active | **core** (already CI gate; pin locally) |

### lsp
| Tool | What | Health | Fit |
|---|---|---|---|
| bash-language-server | Bash LSP: goto-def/hover/rename | active | **core** (backs "LSP-first" mandate; bash-only) |

### templating
| Tool | What | Health | Fit |
|---|---|---|---|
| esh | ERB-style POSIX-shell templating | active | optional (config-gen outside chezmoi) |
| mo | Pure-bash Mustache engine | active | optional (runtime templating if needed) |

### versioning
| Tool | What | Health | Fit |
|---|---|---|---|
| semver_bash | sed parse + compare only | stale | skip (mise/cut-release own this) |
| sh-semver | Range-match filter, no Node | stale | skip (niche, mise pins versions) |

### ui-spinner-color · logging · other
| Tool | What | Health | Fit |
|---|---|---|---|
| ansi | Pure-bash ANSI escapes/cursor | stale | skip (gum covers it) |
| revolver | zsh progress spinner | stale | skip (`gum spin` dup) |
| lumberjack | Leveled `lj` logger | stale | skip (dead-2016; 5-line `log()`) |
| bashful | 2009 bash stdlib bundle | archived | skip |
| Bashlets | Bash OO "stdlib" | stale | skip |
| bash-modules | Strict-mode loader + log/args/test | active | skip (LGPL-copyleft + sourced dep) |
| composure | Function-authoring REPL w/ git | stale | skip (chezmoi/CI already own this) |
| crash | zsh try/catch | stale | skip (zsh-only, `trap ERR`) |
| is.sh | English-prose `test` sugar | stale | skip (cosmetic) |
| phases | `#phase` section runner | stale | skip (no such need) |
| powscript | CoffeeScript→bash transpiler | stale | skip (fights CI; review-generated-bash) |
| shutit | Python/pexpect build framework | stale | skip (wrong category) |

## 4. Adopt now (minimal toolkit, by impact)

```bash
mise use -g shfmt            # (e) the ONE missing piece: auto-format your bash helpers (gofmt-for-shell)
mise use -g shellcheck       # (e) close the local↔CI loop — you lint in CI but can't lint locally today
mise use -g argc             # (a) author multi-subcommand CLIs from inline # @cmd/# @option tags, auto --help
mise use -g bats             # (c) the missing behavioral-test layer; drops into CI as a 3rd step
npm i -g bash-language-server # (e) goto-def/hover/rename for bash, backing your "LSP-first" mandate
```

Then add CI steps mirroring locals: `shfmt -d <bash files>` and a `bats test/` job alongside the existing `shellcheck -S error`. Pin shfmt indent to match house style (`shfmt -i 2 -ci`).

## 5. Gaps & external complements

- **(d) Interactive UX** — no awesome-shell tool worth adopting; **gum** (already pinned, 0.17.0) owns prompts/spinners/styling. Call it *inside* argc command bodies.
- **(f) Logging** — **real gap.** Every researched logger is dead (lumberjack 2016) or encumbered (bash-modules LGPL). Use a hand-rolled leveled `log()` printf helper, or `logger(1)`/`systemd-cat` for journald. Don't adopt a stale tool here.
- **(g) Packaging/distribution** — **real gap.** shellfire `fatten`/rerun archives are stale. You don't need them: argc and bashly already emit a single standalone zero-dep script; ship it via **mise** (version pin) and **chezmoi** (`dot_local/bin/executable_*`). Your `cut-release` skill owns tagging.
- **(h) Templating** — chezmoi `.tmpl` (Go templates) already covers dotfiles; reach for **esh** only when generating config *at runtime from a script* (nginx/systemd), and pin it by sha.

## 6. Skip (one line each)

- **ansi / revolver** — color/spinner duped by gum.
- **bashful / Bashlets / composure / phases / powscript / shutit** — archived/stale "other" tooling solving problems you don't have.
- **bash-modules** — active but LGPL-copyleft + sourced runtime dep; `set -euo pipefail` + getopts replace it.
- **crash** — zsh-only try/catch; native `trap ERR` does it.
- **is.sh / semver_bash / sh-semver** — cosmetic sugar / version work mise + cut-release already own.
- **lumberjack** — dead logger; 5-line `log()` beats it.
- **optparse / dispatch / bashmanager / bashwithnails / rebash / rerun / sub / shellfire** — stale/abandoned scaffolders & parsers; argc/bashly/bashew are the live picks.
- **assert.sh / critic.sh / ts / shpec / urchin / zunit / shunit2** — testing gap is real but bats-core/shellspec (active, mise-installable) beat all of these; **zunit/Fishtape** are also shell-locked (zsh/fish-only).
- **getopts.fish / Fishtape** — fish-only, can't load in zsh/bash.

## 7. Environment findings (live-verified)

- Present: gum (0.17.0), mise, go, node, deno, jq.
- **Absent: shfmt and bats.**
- **shellcheck runs in CI but is not locally installed/mise-pinned** (CI installs via apt) — pinning closes the local↔CI gap.
- All five recommended adds (`argc`, `bats`, `shfmt`, `shellcheck`, `shellspec`) confirmed resolvable in the mise registry; `bashly` is gem-only (Ruby/Docker), which is why **argc** edges it for layer (a) in this environment.
