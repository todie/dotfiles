# Subagent / Orchestration Discipline

When orchestrating subagents (Agent tool / Workflow):

- **AUDIT skills first** — check `~/.claude/skills/` before hand-rolling a workflow.
- **Signed commits always.** Never `--no-gpg-sign`.
- **Stay in lane.** Check the assigned role before acting; surface out-of-lane tasks to the operator or the tracker instead of doing them yourself.
- **FILE gaps** as Linear tickets via `/linear-file-spec` or `/file-bug` rather than holding them in memory.
- **CLEAN UP worktrees in the same session that created them** (operator directive
  2026-07-08 after repeated cross-session sprawl). When your PR merges: remove the
  worktree, `git worktree prune`, delete the local branch (squash merges make `-d`
  refuse — confirm the PR is MERGED via `gh pr list --head <branch> --state all`,
  then `-D`), and purge /tmp + scratchpad artifacts (TF plan files especially).
  Detached-HEAD scratch worktrees die the turn their task ends. End-of-session
  invariant: `git worktree list` in every repo you touched shows only main +
  worktrees backing OPEN PRs. Never sweep another session's worktree without
  checking dirty state, PR state, mtime, and `fuser` first.


