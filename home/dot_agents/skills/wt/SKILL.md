---
name: wt
description: Create a git worktree in a sibling directory with a new branch, and symlink node_modules from the main tree so npm/vite/pnpm builds work without a fresh install. Use when starting isolated feature work in a JS/TS project where reinstalling deps would be slow or break because the worktree is ephemeral. Args — branch name (required), base branch (default main).
---

# wt — git worktree scaffold

Create a git worktree as a sibling directory (`<project>-wt/<name>`) with a new branch off origin, then symlink `node_modules` so the worktree shares installed deps with the main tree. Eliminates the `npm ci` wait and the "my worktree has stale deps because main got a package update after I branched" class of bug.

## When to use

- Starting a feature that touches an existing JS/TS project and you don't want to disturb `main` checkout
- Running experiments in parallel (e.g., two branches open at once)
- Spiking a PR while another long-running thing is in the main tree
- Design passes that need their own preview deploy

**Don't** use this when:
- The project has never been built in the main tree (no `node_modules` to symlink)
- The worktree will add/remove dependencies (symlink would leak changes back)
- You need a pristine fresh install to reproduce a bug — use `git worktree add` without the symlink

## Args

- **branch** (required) — name of the new branch, e.g. `fix/emoji-rendering`. Used as both the branch name and the worktree dir basename (slashes collapsed to dashes).
- **base** (optional, default `main`) — base branch to branch off of. Usually `origin/main` for freshness.

## What it does

1. Find the git root of the current project (`git rev-parse --show-toplevel`).
2. Compute the sibling worktree dir: `<parent-of-git-root>/<project-name>-wt/<branch-sanitized>`.
3. `git fetch origin` to make sure `origin/main` is current.
4. `git worktree add <worktree-dir> -b <branch> origin/<base>`.
5. `ln -sfn ../../<project-name>/node_modules <worktree-dir>/node_modules` so installed deps are shared.
6. Report the new worktree path so you can `cd` into it.

## Usage

Run from inside the project's main tree:

```bash
cd ~/projects/MYPROJECT
ROOT="$(git rev-parse --show-toplevel)"
NAME="$(basename "$ROOT")"
PARENT="$(dirname "$ROOT")"
BRANCH="BRANCH_NAME"
SAFE="$(echo "$BRANCH" | tr '/' '-')"
WT="$PARENT/$NAME-wt/$SAFE"

git fetch origin
git worktree add "$WT" -b "$BRANCH" origin/main

# Symlink node_modules from main tree — saves a full npm install.
ln -sfn "../../$NAME/node_modules" "$WT/node_modules"

echo "Worktree ready: $WT"
```

Then `cd "$WT"` and start working. `npm run build`, `npm run dev`, etc. will see the shared `node_modules` transparently.

## Gotchas

- **Never add or remove dependencies in a symlinked worktree.** Changes to `package.json` without running `npm install` will produce a stale lockfile; running `npm install` in the worktree will write to the symlinked `node_modules`, which leaks into main. If you need to change deps, `rm node_modules` in the worktree first, then run a real install.
- **Worktree already exists** (`fatal: already exists`): `git worktree remove <path>` first, or `git worktree list` to see what's there.
- **Branch already exists**: drop the `-b` flag and reuse the branch, or pick a new name.
- **Cleanup** when you're done: `git worktree remove <path>` from the main tree. The symlink goes with it.

## Why this exists as a skill

The symlink step is the landmine. Without it, `npm run build` inside the worktree fails in non-obvious ways — `Could not resolve "@mdx-js/rollup"` or similar — because vite walks up from the worktree looking for `node_modules` and finds none. The worktree *looks* like a valid repo but isn't buildable. I've hit this twice this week; hence the skill.
