# Changelog

Personal dev-environment config, managed with chezmoi.

**Versioning policy — no semver.** This repo has no external consumers; it's
deployed always-latest via `chezmoi update`, so a MAJOR.MINOR.PATCH contract
carries no signal. Instead:
- **History** is tracked by [Conventional Commits](https://www.conventionalcommits.org/)
  (scoped: `feat(zsh):`, `fix(secrets):`, …).
- **Known-good states** are marked with **CalVer restore tags** (`YYYY.MM.DD`)
  as rollback anchors — `git tag 2026.06.01 && git push --tags`; roll back with
  `chezmoi apply` against that tag.
- This file is a human-readable **narrative**, not a versioned release log.

---

## 2026-06-01 — Kubernetes tooling, mise machine layer, recovery hardening

### Added
- **Kubernetes tooling** end-to-end (#18): krew on PATH, completions for
  kubectl/helm/k9s/stern/kustomize/kubecolor, `kubectl→kubecolor` alias,
  theme-matched k9s skin, context-aware starship prompt.
- **k8s-tools bootstrap + krew completion shims + tests** (#19): pinned,
  checksum-verified installer; `kubectl_complete-*` delegation shims for
  cobra plugins; offline (CI) + opt-in e2e regression tests.
- **Tooling strategy** (#21): layered design — mise (machine) / proto (per-repo
  toolchain) / moon (monorepo) with one global PATH owner. `docs/tooling-strategy.md`.
- **mise machine layer** (#22): mise as the single globally-activated version
  manager; `~/.config/mise/config.toml` pins ~19 CLIs + language runtimes
  (SLSA/checksum-verified), incl. proto/moon; fresh-machine bootstrap run_once.
- **Persisted `~/.claude` config** to chezmoi (#23): CLAUDE.md, RTK.md, rules,
  hooks, authored skills, agents, mcp configs — state/secrets/external excluded.

### Fixed
- **secrets render no longer aborts `chezmoi apply`** when the 1Password
  service-account token is absent (#20): the `secrets.env` template degrades to
  a no-op placeholder instead of erroring the whole apply.
- **`~/.local/bin` wipe (internal):** an e2e test set `BIN=$(mktemp -d)` that the
  sourced bootstrap clobbered back to `~/.local/bin`, so its `rm -rf "$BIN"`
  emptied the dir (twice). Root-caused via canary bisection; fixed by making the
  bootstrap honor a caller `$BIN` + guarding the e2e `rm` to `/tmp` (#19).

### Changed
- **Merge policy → squash-merge** (signed + linear). GitHub's rebase-merge
  produces *unsigned* commits; squash-merge is GitHub-signed and keeps history
  linear, satisfying "all commits signed" + "no merge commits".

### Notes / known gaps
- Fresh-machine reproducibility is asserted, not yet tested end-to-end.
- `~/.agents/` (skills target) and `~/.local/bin` reverie binaries
  (engram/cortex) are owned outside this repo — see the Linear backlog.
