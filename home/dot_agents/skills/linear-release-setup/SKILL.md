---
name: linear-release-setup
description: Generate CI/CD configuration for Linear Release. Use when setting up
  release tracking, configuring CI pipelines for Linear, or integrating deployments
  with Linear releases. Supports GitHub Actions, GitLab CI, CircleCI, and other platforms.
---

# Linear Release Setup

The [linear-release README](https://github.com/linear/linear-release/blob/main/README.md)
is the source of truth for commands, flags, installation, environment
variables, path filtering, and troubleshooting. Fetch it before generating any
config — this skill focuses on the interactive setup workflow and the pipeline
modeling decisions the README cannot make for the user.

**Audited 2026-10-04** against the live
`cerebral-work/linearctl` workflows (`linear-release.yml`, `linear-release-dev.yml`).
Three estate-proven practices from that audit are in "Estate practices" below —
use them in every generated config.

## Interactive Workflow

### Step 1: Preflight

1. **Pipeline exists in Linear** — the user must have created a release
   pipeline in Linear first (Settings → Releases). Each pipeline has its own
   access key.
2. **Detect CI platform** — `.github/workflows/*.yml` (GitHub Actions),
   `.gitlab-ci.yml` (GitLab CI), `.circleci/config.yml` (CircleCI).
3. **Detect default branch** — `git symbolic-ref refs/remotes/origin/HEAD` or
   the CI config. Don't assume `main`.

### Step 2: Map pipelines, then ask

List every build the user ships independently — each becomes its own Linear
pipeline. Pipeline-vs-stage confusion is the most common setup mistake; apply
the test in "Stages vs Pipelines" whenever a split isn't obvious.

Ask, in order:

1. **CI platform** — if not auto-detected.
2. **What do you ship, and to whom?** Prompt for split candidates: production
   vs. beta/TestFlight, nightly/dogfood, staging, per-platform builds,
   per-service in a monorepo. For each: _can these hold different commits at
   the same time?_ Yes → separate pipelines. No → one pipeline with stages.
3. **Per pipeline: continuous or scheduled?**
   - **Continuous** — every deploy completes a release (nightlies, dogfood,
     ship-on-merge web apps).
   - **Scheduled** — releases collect changes and move through stages before
     shipping (versioned mobile, on-prem).
   - The test: does the team need to track a release *before* it ships —
     naming it, seeing what's queued, moving it through phases? Yes →
     scheduled. No → continuous.
4. **Per scheduled pipeline, ask explicitly:**
   - **Branch model** — just `main`, or `main` + `release/*`?
   - **Version source** — calendar, semver, commit SHA? From branch name, CI
     variable, file, or git tag?
   - **Stages** — phases before completion ("code freeze", "in qa")?
   - **Automation** — manual `workflow_dispatch`, or automated promotion?
5. **Monorepo paths** — which paths belong to each pipeline; wire path filters
   in Linear pipeline settings or via `--include-paths`.

### Step 3: Generate the CI configuration

Fetch the README first for current commands, flags, install snippet, and
command-targeting rules. For GitHub Actions use the official action — **pinned
by SHA** (see Estate practices); for other platforms, the CLI binary per the
README's Installation section.

#### Runtime requirements (Docker-based CI)

- **glibc.** The prebuilt binary is dynamically linked against glibc; it will
  not run on Alpine/musl. Pick `debian:bookworm-slim`, `ubuntu:24.04`,
  `buildpack-deps:bookworm`. On musl the failure is an opaque "not found" —
  the glibc loader is absent.
- **`git`.** Slim images lack it: `apt-get update && apt-get install -y git`.
- **`curl`** (or `wget`) to download the CLI.

#### GitLab CI: check existing variables

The linear-release job needs a full clone. Override at job level when project
defaults prevent it: `GIT_STRATEGY: clone` (if the default is `none`/`empty`)
and `GIT_DEPTH: 0` always (new projects default to depth 20).

Example templates (adapt branch patterns, stage names, paths, version format):

| Platform       | Pipeline Type | Example |
| -------------- | ------------- | ------- |
| GitHub Actions | Continuous    | [`github-actions-continuous/`](https://github.com/linear/linear-release/blob/main/examples/github-actions-continuous) |
| GitHub Actions | Scheduled     | [`github-actions-scheduled/`](https://github.com/linear/linear-release/blob/main/examples/github-actions-scheduled) |
| GitLab CI      | Continuous    | [`gitlab-ci-continuous/`](https://github.com/linear/linear-release/blob/main/examples/gitlab-ci-continuous) |
| GitLab CI      | Scheduled     | [`gitlab-ci-scheduled/`](https://github.com/linear/linear-release/blob/main/examples/gitlab-ci-scheduled) |
| CircleCI       | Continuous    | [`circleci-continuous/`](https://github.com/linear/linear-release/blob/main/examples/circleci-continuous) |
| CircleCI       | Scheduled     | [`circleci-scheduled/`](https://github.com/linear/linear-release/blob/main/examples/circleci-scheduled) |

Multiple pipelines → multiple workflows or jobs, each with its own access key
(one secret per pipeline, e.g. `LINEAR_ACCESS_KEY_IOS`, `LINEAR_ACCESS_KEY_WEB`).

### Step 4: Remind about secrets

`LINEAR_ACCESS_KEY` goes into CI secrets (GitHub: Settings → Secrets and
variables → Actions; GitLab: Settings → CI/CD → Variables; CircleCI: Project
Settings → Environment Variables). The key comes from the pipeline's settings
page in Linear — one per pipeline.

## Estate practices (audited 2026-10-04, cerebral-work/linearctl)

1. **Pin the action by SHA**, not tag:
   `uses: linear/linear-release-action@c0cb8354a362c24c6d3e0948f37fd66d07588e3f # v0`.
   Same rule for `actions/checkout` and every third-party action.
2. **Dormant-until-keyed gate.** First step checks the secret and short-
   circuits the job (`enabled=true/false` output) so an unprovisioned pipeline
   never red-X's releases:

   ```yaml
   - id: gate
     env: { LINEAR_ACCESS_KEY: ${{ secrets.LINEAR_ACCESS_KEY } }
     run: |
       if [ -z "${LINEAR_ACCESS_KEY:-}" ]; then
         echo "::warning::LINEAR_ACCESS_KEY not set — skipping Linear release sync."
         echo "enabled=false" >> "$GITHUB_OUTPUT"
       else
         echo "enabled=true" >> "$GITHUB_OUTPUT"
       fi
   ```

   Every later step gets `if: steps.gate.outputs.enabled == 'true'`.
3. **release-please tags don't trigger `push: tags` workflows** — GitHub by
   design does not fire them from `GITHUB_TOKEN`-created events. A tag trigger
   silently never runs. Make the Linear workflow a **reusable workflow**
   (`on: workflow_call` + `workflow_dispatch` for manual re-syncs) invoked by
   the release workflow in the same run that creates the release.
4. **Sync then complete on tagged releases** (tag-driven guidance from the
   README): `command: sync` followed by `command: complete`; sync alone leaves
   the release in-progress. `continue-on-error: true` on both — release
   *reporting* must not fail the release.
5. **Dev mirror pipeline**: a continuous `<name>-dev` pipeline synced on every
   push to main (`version: dev-${GITHUB_SHA::7}`) with its own secret
   (`LINEAR_ACCESS_KEY_DEV`), so in-flight issue linkage is visible before a
   tagged release.
6. **`fetch-depth: 0`** on checkout — the CLI scans commits back to the prior
   release.

## Key Concepts

A Linear **release pipeline** is one independent stream of releases, with its
own version history, current release, and access key. Not a CI pipeline — the
unit Linear tracks releases with; your CI calls the CLI to update it.

### Stages vs Pipelines

A **stage** is one phase inside a release on one pipeline. The test: can two
things be in-flight at the same time, holding different commits?

- **Yes** → separate pipelines (TestFlight on `HEAD` while prod ships 1.2;
  staging auto-deploying `main` while prod lags; a hotfix in one stream only).
- **No — same build moving through gates** → one pipeline with stages ("code
  freeze", "in qa", "rc soak"). Stages exist only on scheduled pipelines.

Ambiguous cases:

- **Beta/TestFlight** — soak before GA on the _same build_ → stage; a distinct
  nightly channel → pipeline.
- **Staging** — auto-deploys `main` or runs hotfixes prod lacks → pipeline;
  same build earlier in the path → stage.
- **Per-service monorepo** — each independently-shipped service → its own
  pipeline, path-filtered. Services are never stages.

A **frozen** stage makes `sync` (without `--release-version`) skip that
release and land commits on the next one — a code-freeze safety net, not a way
to squeeze two pipelines into one.

## Reference

Commands, flags, env vars, command targeting, path filtering, JSON output, and
troubleshooting live in the [linear-release README](https://github.com/linear/linear-release#readme);
action inputs map to CLI flags per the [action README](https://github.com/linear/linear-release-action#inputs).
Fetch these rather than trusting memory — they move ahead of this skill.

### Checklist

- [ ] Full clone / `fetch-depth: 0` (GitLab: `GIT_DEPTH: 0`, `GIT_STRATEGY` not `none`)
- [ ] One `LINEAR_ACCESS_KEY*` secret per pipeline
- [ ] Action pinned by SHA; dormant-until-keyed gate on every step
- [ ] Not tag-triggered if release-please (or any token-created tag) cuts the release
- [ ] Correct binary platform (`linux-x64`, `darwin-arm64`, `darwin-x64`)
- [ ] Docker CI: glibc base (no Alpine/musl) with `git` + `curl`
- [ ] Triggers on the right branches (`main` for continuous; `main` + `release/*` for scheduled)
- [ ] Monorepo: path filters set, separate workflows if using release branches

## Example script

`scripts/check-linear-release-setup.sh [repo-root]` — audits an existing
`.github/workflows/linear-release*.yml` against the checklist above (read-only;
exits non-zero on any miss).
