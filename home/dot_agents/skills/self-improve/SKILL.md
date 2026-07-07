---
name: self-improve
description: Record a lesson, correction, or newly discovered stable fact into the harness's permanent memory — machine-wide lessons go to ~/.pi/agent/AGENTS.md (Lessons section), project-specific lessons to the project's AGENTS.md, and repeated workflows get promoted to a new skill in ~/.agents/skills/. Use whenever the user corrects the agent, when the agent repeats a mistake it made in a previous session, when a non-obvious fact about this machine/tooling is discovered, or when the user says "remember this", "don't do that again", or "make this a skill". Args — lesson text (required), optional --scope global|project (default inferred), optional --promote <skill-name> to create a skill instead of a lesson line.
---

# Self-Improve

Close the loop: mistakes and discoveries become permanent instructions so no
future session repeats them.

## Decision tree

1. **Is it a one-line fact or rule?** → append a lesson line.
   - Machine-wide (tools, auth, storage, OS quirks) → `~/.pi/agent/AGENTS.md`,
     under `## Lessons`.
   - Project-specific (build commands, conventions, gotchas) → `AGENTS.md` at
     the project root (create with a `# <project> — Agent Notes` header and a
     `## Lessons` section if missing).
2. **Is it a repeatable multi-step workflow?** → promote to a skill:
   create `~/.agents/skills/<name>/SKILL.md` with spec-compliant frontmatter
   (`name`: lowercase-hyphens; `description`: what it does AND when to use it,
   including trigger phrases and args). Helper scripts go in the same dir.
3. **Does it contradict an existing lesson?** → replace the old line, don't
   append a duplicate; note the supersession in the new line.

## Lesson line format

```
- YYYY-MM-DD: <imperative rule, one or two lines, concrete enough to act on>
```

Bad: "be careful with paths". Good: "quote output paths passed to heretic
--save-path; unquoted tilde created a literal ./~ dir in the repo".

## After writing

- Confirm to the user what was recorded and where.
- If a new skill was created, remind that `/reload` (or a new session) picks it up.

## Periodic audit (run when the user asks for a "harness audit")

1. Read `~/.pi/agent/AGENTS.md` and prune stale/contradictory lessons.
2. `ls ~/.agents/skills/` — flag skills whose descriptions no longer match
   reality (moved paths, dead tools).
3. Check `~/.pi/agent/settings.json` against
   `<pi-install>/docs/settings.md` for invalid or risky values
   (e.g. `defaultProjectTrust: "always"`).
4. Report findings and apply fixes the user approves.
