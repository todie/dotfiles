---
name: preview-url
description: Fetch the Cloudflare Pages (or Vercel, or any CI bot) preview URL from the sticky PR comment on a pull request. Use when you just pushed to a PR branch and need the live preview URL without opening the browser. Works against any PR that uses a marker-based sticky comment pattern. Args — pr number (optional, defaults to the PR for the current branch), marker (optional, defaults to `<!-- impeccable-preview -->`).
---

# preview-url

Fetch a PR's sticky preview-deploy comment and extract the preview URL from it. The CI workflow in todie/explainers (see [.github/workflows/ci.yml](https://github.com/todie/explainers/blob/main/.github/workflows/ci.yml)) posts a comment keyed by `<!-- impeccable-preview -->` containing the CF Pages branch-alias URL. This skill reads that comment and returns the URL.

## When to use

- You just pushed to a PR branch and want the preview URL to `Read` a snapshot of
- The user asks "where's the preview?" or "is this live yet?"
- You need to pipe the URL into `/snapshot`

**Don't** use this for:
- Production URLs (those are static — just use them directly)
- First-deploy PRs before the CI has finished — wait for the workflow to complete first, or the comment won't exist yet

## Args

- **pr** (optional) — PR number. If omitted, look up the PR for the current branch with `gh pr view --json number -q .number`.
- **marker** (optional) — the HTML comment marker used as the sticky-comment key. Defaults to `<!-- impeccable-preview -->`. Override for projects using a different marker (Vercel, Netlify, custom bots).

## Usage

```bash
PR="${1:-$(gh pr view --json number -q .number)}"
MARKER="${2:-<!-- impeccable-preview -->}"

gh pr view "$PR" --json comments \
  -q ".comments[] | select(.body | contains(\"$MARKER\")) | .body" \
  | grep -oE 'https://[a-zA-Z0-9.-]+\.pages\.dev[^ )]*' \
  | head -1
```

Pipes the body of the matching sticky comment through `grep -oE` to pull out the first Cloudflare Pages URL. Returns empty if no matching comment exists yet — means CI hasn't posted it or the workflow is still running.

## Variants

**Check CI status first, then fetch URL:**
```bash
gh pr checks "$PR"  # make sure build + preview jobs are green
# then run the extraction above
```

**Different provider URL patterns:**
- Cloudflare Pages: `https://<slug>.<project>.pages.dev`
- Vercel: `https://<slug>-<project>.vercel.app`
- Netlify: `https://<slug>--<project>.netlify.app`

Adjust the grep regex to match the provider in the comment body:
```bash
# Vercel
grep -oE 'https://[a-z0-9-]+\.vercel\.app[^ )]*'
# Netlify
grep -oE 'https://[a-z0-9-]+--[a-z0-9-]+\.netlify\.app[^ )]*'
```

## Common failure modes

- **Empty output** — no sticky comment yet. Run `gh run list --branch $(git branch --show-current) --limit 1` to check the workflow status.
- **Wrong URL returned** — there's more than one matching comment (e.g., the sticky isn't updating in place). `gh pr view $PR --json comments -q '.comments[-1].body'` falls back to the newest comment.
- **`gh` not logged in** — `gh auth status`. If the PR is in a different repo, `gh pr view -R owner/repo $PR`.
