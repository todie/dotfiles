# claude/

Claude Code harness configuration — hooks, helper scripts, and (eventually)
settings for the Claude CLI / agent SDK environment.

## Layout

```
claude/
├── hooks/
│   └── guard-dangerous-commands.sh   PreToolUse Bash hook: blocks dangerous
│                                     commands (DROP TABLE, force-push main,
│                                     curl|bash, rm -rf home) and prevents
│                                     leaking secret-named env vars (R1–R4).
└── bin/
    └── claude-secret-test            Regression test runner for the secret-
                                      leak guard. 35 cases covering all 4
                                      rules + edge cases. Exits 0 on pass,
                                      1 on any failure (CI-friendly).
```

## Why this exists

On 2026-04-06 I leaked an `ANTHROPIC_API_KEY` to tool output via a buggy
`${VAR:+yes}${VAR:-no}` pattern — the `${VAR:-fallback}` form returns the
*value* when set, not the literal "no". The lesson: instruction-layer rules
in `CLAUDE.md` only work if the model reads and obeys them. A `PreToolUse`
hook is hard enforcement at the harness layer — the model literally cannot
execute the bad pattern, even if it forgets the rule.

## What the hook blocks

| Rule | Pattern | Why |
|------|---------|-----|
| R1   | `${SECRETVAR:-fallback}` with non-empty fallback | The original bug. `:-` returns the value when set. |
| R2   | `echo`/`printf` of `$SECRETVAR` or `${SECRETVAR}` | Direct value emission. Allows the safe `${VAR:+word}` form. |
| R3   | `printenv SECRETVAR` | Same effect as R2. |
| R4   | `env \| grep SECRETVAR` | Dumps full `VAR=value` line. |

The hook also preserves the existing destructive-command rules: DROP TABLE,
force-push to `main`/`master`, redirects to `~/.ssh`/`~/.gpg`/`~/.secrets`/
`~/.gitconfig`, `curl|bash` / `wget|sh`, `rm -rf` of home or root.

## Secret-name detection

A variable is "secret-named" if its identifier *ends* with one of:
`KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `PASSWD`, `CRED`, `PRIVATE`, `APIKEY`.
Case-insensitive (so `api_key` and `github_token` are caught).

End-anchored, so:

| Variable | Verdict |
|----------|---------|
| `MY_API_KEY`        | blocked (KEY at end) |
| `GH_TOKEN`          | blocked |
| `RESET_PASSWORD`    | blocked |
| `api_key` (lowercase) | blocked (case-insensitive) |
| `KEYBOARD_LAYOUT`   | allowed (KEY at start) |
| `TOKENS_PROCESSED`  | allowed (TOKEN at start) |
| `KEYS_DIR`          | allowed (KEYS plural at start) |
| `PASSWORD_RESET_URL`| allowed (ends in URL) |

## Bypass

Append `# allow-secret-print` at end-of-line if you really need to print
a secret env var (e.g., generating credentials for testing). The hook
only honors the sentinel at end-of-line, so an in-string occurrence
(`echo "see # allow-secret-print docs"`) cannot smuggle a bypass.

## User-visible notification

When the hook blocks, it writes a red banner to `/dev/tty` (so you see it
in your terminal, distinguishable from other tool failures) AND appends
to `~/.claude/logs/secret-guard.log` for grepable history.

## Testing

```bash
claude-secret-test            # run all 35 tests
claude-secret-test --list     # show test names + expected outcomes
claude-secret-test --verbose  # show input + stderr for every test
claude-secret-test --help
```

All test cases use **fictional** env-var names (`FAKE_API_KEY`, `SAMPLE_TOKEN`,
`DEMO_TOKEN`, …) so the runner has zero overlap with real provider naming.
The hook itself only inspects command STRINGS — it never reads env values.

Run the test suite after any edit to `guard-dangerous-commands.sh` or after
upgrading Claude Code. CI hooks should call it as a smoke test.

## Wiring

The hook is wired into Claude Code via `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "/home/ctodie/.claude/hooks/guard-dangerous-commands.sh",
        "timeout": 3
      }]
    }]
  }
}
```

`settings.json` is **not** tracked here yet — it contains marketplace
configuration and other personal state. Add it later if you want full
config-as-code coverage.

## Future additions

- `claude/CLAUDE.md` — global instructions (currently lives at `~/.claude/CLAUDE.md`)
- `claude/rules/*.md` — per-language style rules
- `claude/RTK.md` — RTK reference
- `claude/hooks/notify.sh`, `engram-start.sh`, etc. — other hooks

Each addition needs a corresponding `link` call in `install.sh`.
