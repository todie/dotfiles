# CER-1097 shim snapshot — 2026-07-27

Reference copies of the thin-shim guard hooks produced by the CER-1097
shadow→enforce cutover. **Not deployed** — this directory sits outside the
`.chezmoiroot=home` tree, so `chezmoi apply` never reads it.

## Why this exists

The cutover was applied directly to a live `~/.claude/hooks/` on ceres and
never committed anywhere. When the hooks were restored to their pre-cutover
versions on 2026-07-27, these four files were the **only copies in existence**.
They are archived here so the work is not lost.

| file | lines | vs pre-cutover |
|---|---|---|
| `guard-dangerous-commands.sh` | 120 | 170 |
| `worktree-jail.sh` | 69 | 127 |
| `guard-secret-access.sh` | 78 | 170 |
| `guard-hook-immutable.sh` | 52 | new — no predecessor |

## Do not deploy these as-is

They are archived as a design reference, not as a rollback target. Review
found each of them loses coverage relative to what they replaced:

- `guard-dangerous-commands.sh` `exec`s `reverie-guard` in enforce mode, so
  every rule below that line — destructive-DB, critical-dotfile writes, all
  secret-leak rules — becomes unreachable, while the file's own header claims
  the fallback still carries them.
- Shadow mode invokes the binary with `</dev/null`, so it never sees the
  command and collects no telemetry.
- `guard-secret-access.sh` reads `.file_path` / `.path` from the envelope root
  instead of `.tool_input.*`, making the Read/Grep secret guard dead code.
- `worktree-jail.sh` has no `Bash)` case at all; jail-escape detection is
  absent and `reverie-guard` does not implement it.
- `guard-hook-immutable.sh`'s glob is `*/.claude/hooks/*`, which misses
  `rm -rf ~/.claude/hooks` — the one command that removes every guard.

The architecture also assumes `reverie-guard` is deployed and enforcing. It is
not, and its rule engine has seven independently verified bypasses. Enforce
must stay off on every host until those are fixed behind a differential test
corpus.

Refs: CER-1097 (cutover), CER-1741 (never round-tripped), CER-1743 (ceres
disarmed), CER-1744 (guard rule bypasses).
