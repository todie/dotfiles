---
name: ci-merge
description: >
  Watch a PR's CI checks, review if green, and merge. Use when a PR is pushed
  and you want to auto-merge once CI passes. Handles the gh run watch → review
  → merge → pull main flow.
allowed-tools:
  - Bash
tags: [ci, pr, merge, github]
---

# CI Watch + Review + Merge

## Usage

Invoke with a PR number: `/ci-merge 75`

If no PR number given, detect from the current branch.

## Steps

1. Get the latest CI run for the PR branch:
   ```bash
   gh run list --branch <branch> --limit 1 --json databaseId,status,conclusion
   ```

2. If in_progress, watch it:
   ```bash
   gh run watch <run-id> --exit-status
   ```

3. If all checks pass:
   ```bash
   gh pr review <pr> --approve --body "CI green, LGTM"
   gh pr merge <pr> --squash --delete-branch
   ```

4. Pull main:
   ```bash
   git checkout main && git pull origin main
   ```

5. If checks fail, show the failures:
   ```bash
   gh run view <run-id> --log-failed | grep -E 'error\[|^error:' | head -20
   ```

## Gotcha

`gh run watch` without a run ID watches the OLDEST in-progress run, which may
be a stale failed run. Always specify the run ID explicitly.
