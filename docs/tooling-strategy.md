# Tooling pinning strategy — research & recommendation

_Status: proposal for discussion. Researched 2026-06-01 (mise & proto docs via
Context7; proto third-party registry fetched & coverage-checked). No changes
applied — design pass only._

## Why this exists

`~/.local/bin` was a pile of hand-installed binaries with **no manifest**. When
it was emptied (a destructive bug in a test — see git history), nothing could say
what *should* be there; recovery was archaeology. Goal: a **declarative, pinned,
checksum-verified, reproducible** tool set that one command restores after a wipe
or on a fresh box — and that also serves the **~40 repos under `~/projects`**,
several of which are monorepos that want real build/task orchestration.

Decision (operator): use **mise + proto + moon**, each in its own lane. This doc
defines the lanes so they don't fight.

## The three tools have distinct domains

| Tool | Layer | Owns | Scope |
|------|-------|------|-------|
| **chezmoi** | config | dotfiles → `$HOME` (real files) | machine |
| **mise** | machine toolchain | the CLIs + default language runtimes that live on PATH everywhere | **global** |
| **proto** | project toolchain engine | per-repo language/tool versions; the engine moon drives | **per-repo** |
| **moon** | monorepo orchestration | task graph, build caching, CI, project boundaries | **per-monorepo** |

The trap with "two version managers" is **two things racing on `PATH`**. The rule
that prevents it: **exactly one globally-activated manager — mise.** proto is
*not* globally activated; it exists as moon's toolchain provider and (optionally)
activates only inside monorepo directories. One PATH owner per directory.

## Layered architecture

```
chezmoi  ── delivers ──▶  ~/.config/mise/config.toml   (global tool manifest, committed)
                                   │
mise (global, the only `… activate` in .zshrc)
   ├── machine CLIs        kubectl, helm, k9s, kustomize, terraform, stern, jq, uv, direnv, fzf, btop, gh …
   │      (backend: aqua → SLSA + checksums; github → for the rest)
   ├── default languages   node, python, go, rust(toolchain), bun, deno
   └── installs the next layer:  proto, moon          ← mise pins proto & moon themselves
                                   │
        ┌──────────────────────────┴───────────────────────────┐
   proto (per-repo .prototools)                         moon (.moon/ per monorepo)
   pins THIS repo's node/bun/rust/…                     task graph + caching + CI;
   (moon uses proto as its toolchain provider)          drives proto for toolchains
```

Bootstrap chain on a fresh machine (single path, no archaeology):
`chezmoi init --apply` → `run_once` installs mise → `mise install` reads the
global manifest → among the tools it installs are **proto and moon** → entering a
monorepo, `moon` uses `proto` + that repo's `.prototools`.

## Lane assignments (your actual tools)

**mise — machine layer** (`~/.config/mise/config.toml`, chezmoi-managed, pinned):
- aqua backend (SLSA-verified): `kubectl, helm, k9s, kustomize, terraform, sops,
  stern, jq, uv, direnv, fzf, btop, gh` — all confirmed in aqua/registry.
- github backend: anything not in aqua.
- default language runtimes: `node, go, rust, bun, deno, python`.
- pins `proto` and `moon` themselves (so the monorepo layer is also pinned).

**Kept OFF mise, on the `run_once` checksummed installer** (provenance-sensitive
or no trustworthy registry entry):
- **`op` (1Password CLI)** — explicitly NOT via a community plugin/registry; it
  guards every other secret. Stays on an installer with a URL + checksum I control.
- `kubecolor` — no aqua/registry entry today (verified); already on the installer.
- (revisit each if/when a first-party, checksummed source appears.)

**proto + moon — monorepo layer** (committed to *each monorepo*, not dotfiles):
- `.prototools` pins that repo's toolchain; `.moon/` defines tasks/projects.
- Nothing here touches `~/.local/bin` or the global shell.

**Custom Rust binaries** (`engram`, `cortex`, `reverie-*`) — **stay on the deploy
skills** (`deploy-reverie` / `reveried-swap` + `cargo install --path`), per your
call. Not a registry concern; they're first-party builds.

## Conflict-avoidance details (the crux of "why not all three")

1. **One global activation.** `.zshrc` runs `mise activate zsh` only. proto is
   installed but **no global `proto activate`** and **no proto shims on the global
   PATH**.
2. **Monorepo handoff — pick one:**
   - **(A) moon-as-entrypoint (simpler, recommended to start):** inside a
     monorepo you run tasks via `moon run …`, which uses proto-pinned toolchains.
     Ad-hoc `node`/`bun` in that dir resolves to mise's global default. Acceptable
     because moon is the work entrypoint; optionally mirror the repo's major
     runtime in mise so ad-hoc use matches.
   - **(B) per-dir activation (seamless, later):** a `.envrc` (direnv — itself
     mise-managed) runs `proto activate` inside the monorepo, so `.prototools`
     wins there and mise resumes outside. Exactly one manager active per dir.
3. **No double-pinning of the same tool in both mise and a repo's `.prototools`
   for the same scope** — global default in mise, per-repo override in proto.
4. **chezmoi owns only the *global* manifest** (`~/.config/mise/config.toml`).
   `.prototools`/`.moon/` belong to each project repo, not dotfiles.

## Recovery story (what a future wipe looks like)

`chezmoi apply` → `run_once` reinstalls mise + the checksummed `op`/`kubecolor` →
`mise install` restores every pinned CLI + language + proto + moon from the
committed manifest. Monorepos restore their own toolchains via `moon`/`proto` on
next use. The custom Rust trio via the deploy skills. **No archaeology.**

## Decisions (resolved 2026-06-01)

1. **Monorepo handoff → (A) moon-as-entrypoint.** `moon run` uses proto-pinned
   toolchains; ad-hoc invocation uses mise's global default. (B) direnv per-dir
   activation remains a future upgrade if seamlessness is wanted.
2. **gh → mise.** Moved off apt into the pinned mise manifest (aqua/SLSA) for one
   consistent, version-pinned, wipe-recoverable source.
3. **Architecture approved** — proceed to build the machine layer (mise + pinned
   `config.toml` + `run_once` bootstrap) as the first implementation PR.

### Still deferred (per-repo / follow-up)
- **Which repos under `~/projects` are moon monorepos** — adopt per-repo,
  deliberately, not blanket. Out of scope for dotfiles.
- **Exact manifest tool list + pinned versions** — built in the machine-layer PR
  and reviewed there; this doc fixes the architecture, not the version numbers.

## What this doc does NOT do

No installs, no `config.toml`, no `.prototools`, no shell changes. It fixes the
**lanes**. Implementation follows in separate, reviewable PRs once the open
decisions above are settled — machine layer (mise + manifest + bootstrap) first,
monorepo layer (proto/moon) per-repo as you adopt it.
