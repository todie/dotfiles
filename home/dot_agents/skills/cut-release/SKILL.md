---
name: cut-release
description: Bump the project's semver version, update CHANGELOG.md, update Helm chart version (if present), update Cargo.toml/package.json/pyproject.toml/VERSION (whichever is the canonical source), commit, and tag — all in one shot. Stops short of pushing. Use when the user says "cut a release", "release v0.2.0", "bump the version and tag", "release patch/minor/major". Auto-detects the GitHub remote for CHANGELOG link rewriting. Generic across Rust / Node / Python / Go / Helm / multi-language repos. Args — bump=patch|minor|major|<explicit-version> (required).
---

# Cut Release

Bundle the "prepare a release" workflow into a single command. Bump the version in whichever canonical files exist, update `CHANGELOG.md` to roll the `[Unreleased]` section into a new dated version, update the Helm chart if present, commit everything, and tag.

**Stops short of pushing.** The user runs `git push origin main --tags` (or `gh release create`) themselves once they've reviewed.

## When to use

- User asks to "cut a release", "release a patch", "bump version and tag", "release v0.2.0"
- User has a `CHANGELOG.md` with `[Unreleased]` content ready to ship
- User wants the bundle done atomically rather than typing 6-7 commands

**Don't** use this for:
- Repos with no `CHANGELOG.md` — the script needs `[Unreleased]` content to roll over
- Repos that use `release-please` or `cargo-release` already (those tools own the workflow — don't fight them)
- The actual `git push` step (deliberately not automated; the user reviews first)
- Cargo workspace-style repos with multiple crates each having their own version (this script bumps ONE canonical version source — see "Multi-version repos" below)

## What it does

1. **Detect canonical version source**, in priority order:
   - `VERSION` file (plain text, single line) — preferred for projects without a package manager
   - `Cargo.toml` workspace `[workspace.package]` version → updates `version = "..."`
   - `Cargo.toml` package `[package]` version (single-crate Rust)
   - `package.json` `version` field
   - `pyproject.toml` `[project]` or `[tool.poetry]` version
   - Falls back to "no canonical source" error if none found
2. **Compute the new version** from the bump argument:
   - `patch` → `major.minor.(patch+1)`
   - `minor` → `major.(minor+1).0`
   - `major` → `(major+1).0.0`
   - explicit semver string → use as-is
3. **Update the canonical version file** in place
4. **Update `helm/Chart.yaml`** if present (both `version` and `appVersion`)
5. **Roll `CHANGELOG.md`** — replaces the `[Unreleased]` header with `[Unreleased]\n\n## [NEW] - DATE`. Updates the compare links at the bottom using `git remote get-url origin` to detect the GitHub repo URL.
6. **Stage and commit** with message `Release vNEW`
7. **Create an annotated tag** `vNEW`
8. **Print the next steps** the user needs to run manually (push, gh release create, undo)

## Usage

The skill ships a single shell script. Invoke from the project root:

```bash
~/.agents/skills/cut-release/scripts/cut-release.sh patch    # 0.1.0 → 0.1.1
~/.agents/skills/cut-release/scripts/cut-release.sh minor    # 0.1.0 → 0.2.0
~/.agents/skills/cut-release/scripts/cut-release.sh major    # 0.1.0 → 1.0.0
~/.agents/skills/cut-release/scripts/cut-release.sh 0.2.0    # explicit
```

The script:
- Refuses to run if the working tree has uncommitted non-version changes
- Refuses to run if `CHANGELOG.md` doesn't have an `[Unreleased]` section with content
- Refuses to run if the resulting version isn't strictly greater than the current
- Always prints what it's about to do BEFORE doing it (with a `--dry-run` flag for paranoid invocations)

## Multi-version repos

If the repo has multiple version sources (e.g. a Cargo workspace with several crates each at their own version, or a monorepo with package.json + pyproject.toml + Cargo.toml all independently versioned), the script bumps the FIRST canonical source it finds in priority order and warns about the others. For genuine multi-package monorepos, consider `release-please` or `lerna` instead.

## Failure modes

- **No `CHANGELOG.md`**: errors out. Pact convention is to maintain CHANGELOG.md proactively (see global feedback memory `feedback_always_changelog`).
- **No `[Unreleased]` content**: errors out. Don't release a version with no changes.
- **Dirty working tree (other than version files)**: errors out. Commit or stash first.
- **Invalid bump argument**: prints usage and exits.
- **Helm Chart.yaml exists but has unusual format**: warns and skips it. Doesn't break the release.

## Safety

- Doesn't push. Doesn't run `gh release create`. Doesn't touch CI.
- Prints exact undo commands at the end (`git reset --soft HEAD~1 && git tag -d vNEW`).
- Annotated tag (not lightweight) so the tag carries metadata.
