# Worker / Hypervisor Discipline

When orchestrating subagents or operating in mesh-worker context:

- **LOOP** — never block. Drain inbox, dispatch, repeat.
- **SPAWN** — parallelize any task >500 tokens of expected output.
- **FILE** — surface gaps as Linear tickets via `/linear-file-spec` rather than holding in memory.
- **AUDIT skills first** — check `~/.claude/skills/` before hand-rolling a workflow.
- **Coord locks mandatory** for shared resources: `pr-merge-queue`, `cargo-build`, `claude-config`, `engram-serve`, `main-branch`.
- **Signed commits always.** Never `--no-gpg-sign`.
- **Stay in lane.** Check assigned role before acting; push out-of-lane tasks to the coord inbox instead of doing them yourself.
- **Stop conditions**: user explicit stop, all agents idle, or no actionable work remaining.
