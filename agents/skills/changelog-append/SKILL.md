---
name: changelog-append
description: Append an entry to the [Unreleased] section of CHANGELOG.md at the repo root. Creates CHANGELOG.md with Keep-a-Changelog scaffolding if it doesn't exist. Use any time a user-visible change is about to be committed — the changelog update must go in the SAME commit as the change, per the always-changelog feedback rule. Args — section (added|changed|fixed|removed|deprecated|security), bullet (the entry text, without the leading '-').
---

# changelog-append

Append a single bullet to the appropriate subsection of `## [Unreleased]` in `CHANGELOG.md` at the repo root. Enforces the "always changelog" workflow rule by making the append a one-liner instead of a file-read-edit-write dance.

## When to use

- **Every user-visible change** — in the same Edit block as the change itself, before `git commit`
- When a PR description says "Added X" or "Fixed Y", mirror that into `CHANGELOG.md` too
- When the user says "changelog this" or "log this change"

**Don't** use this for:
- Internal refactors the user would never notice
- Test-only changes
- CI workflow tweaks that don't affect users
- Pure docs/comment changes (unless they're user-facing docs)

## Args

- **section** (required) — one of: `added`, `changed`, `fixed`, `removed`, `deprecated`, `security`. Maps to the corresponding `### Added` / `### Changed` etc. subsection under `[Unreleased]`.
- **bullet** (required) — the entry text. Single sentence, user-perspective, no leading `-`. The skill will prepend `- ` automatically.

## Behavior

1. Find `CHANGELOG.md` at the git root.
2. If it doesn't exist, create it with a standard Keep-a-Changelog header and an empty `[Unreleased]` section with all six subsections as empty stubs.
3. Find the `## [Unreleased]` section.
4. Find the `### <Section>` subsection under it. If that subsection doesn't exist (because it was empty and got collapsed), insert it in the canonical order: Added → Changed → Deprecated → Removed → Fixed → Security.
5. Append `- <bullet>` to the end of the subsection's bullet list.

## Typical sequence

In a single commit, the author:
1. Makes the code change (Edit / Write)
2. Runs the changelog append
3. Stages both in one `git add`
4. Commits with a message that matches the changelog entry

## Usage

Given `section=added` and `bullet=Twemoji-based <Emoji> component for consistent color emoji rendering.`, the resulting change to `CHANGELOG.md` looks like:

```diff
 ## [Unreleased]

 ### Added
 - Existing entry.
+- Twemoji-based <Emoji> component for consistent color emoji rendering.

 ### Changed
```

The `Edit` tool is the right primitive for the append. Use `old_string` to target the last bullet in the subsection (or the `### <Section>` header if the subsection is empty) and `new_string` to include the original plus the new bullet.

## Scaffolding new file

If `CHANGELOG.md` doesn't exist, write:

```markdown
# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

### Changed

### Fixed

### Removed

### Deprecated

### Security

---
```

Then append the user's bullet under the right subsection.

## Release-cut

When releasing: rename `[Unreleased]` to `[X.Y.Z] — YYYY-MM-DD` and add a fresh empty `[Unreleased]` above it with all six empty subsections. That's a separate operation from append — don't automate it into this skill unless the user asks.

## Why this exists as a skill

The always-changelog rule (see `feedback_always_changelog` memory) is only useful if it's cheap to comply. Without a skill, every commit ritual becomes: find CHANGELOG → read it → locate the right subsection → craft the edit → stage. Five steps for one bullet. A skill collapses it to "call /changelog-append added '...'" which is frictionless, which is what keeps the rule alive.
