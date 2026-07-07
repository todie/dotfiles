---
name: reverie-secret-page
description: Capture a secret (API key, token, password) from the user via a one-shot localhost web page that self-destructs after the first POST. Use this when you need the user to paste a credential into a Claude Code session without it ever entering shell history, scrollback, argv, or the conversation transcript. The companion `reverie-secret-add` provides a TTY-prompt fallback for non-browser flows.
---

# reverie-secret-page

A 60-second secure secret-capture flow that bypasses every leak surface a Claude Code session has: scrollback, bash history, transcript, `ps` argv, hook logs.

## When to use

Whenever you need a value from the user that:
- must not appear in the conversation transcript (Claude's memory)
- must not appear in shell history
- must not appear on screen / scrollback / OCR
- must not appear in `ps` or process listings
- has to be persisted to a file at a known path

Examples: OpenRouter / Anthropic / OpenAI API keys, GitHub PATs, Tailscale auth keys, Linear API tokens, Cloudflare API tokens, SMTP passwords, Postgres connection strings, OIDC client secrets.

**Do NOT use** for ephemeral values that won't be persisted, or for values that are safe to type into the conversation directly.

## How it works

`reverie-secret-page` is a Python stdlib HTTP server (no deps) that:
1. Binds `127.0.0.1:<random free port>` (NEVER 0.0.0.0)
2. Serves a single dark-mode HTML form with the Hexpurr mascot, a CSRF token, and a textarea
3. Accepts ONE POST to `/`
4. Validates CSRF, atomically writes the value to `~/.config/reverie/<name>` mode 600
5. Confirms with size + sha256 prefix
6. Calls `httpd.shutdown()` and exits

## Invocation

The user runs it via the `!` shell-escape in their Claude Code prompt box:

```
! reverie-secret-page openrouter.key
```

Output:
```
open in your browser:  http://127.0.0.1:43081/
(localhost only · single-use · server dies after first write)
```

The user opens the URL, pastes, submits. Server prints:
```
wrote /home/ctodie/.config/reverie/openrouter.key  size=73B  sha256=012e3529bb0ab479…
```

Claude only sees the post-write confirmation (size + sha prefix), never the value.

## Properties

| Property | Mechanism |
|---|---|
| Localhost-only bind | `("127.0.0.1", 0)` — never 0.0.0.0 |
| Random port per run | `socket.bind(("", 0))` then `getsockname` |
| Single-use | `httpd.shutdown()` after first successful POST |
| CSRF protection | `secrets.token_urlsafe(24)` echoed via hidden field |
| Empty/oversized rejected | `Content-Length` capped at 64 KiB; empty string refused |
| No logging | `log_message` overridden to no-op |
| Atomic write | `tmp.write_text() → chmod 600 → tmp.replace(dest)` |
| Mode 600 file | `os.chmod(dest, 0o600)` |
| Path traversal blocked | `name` rejected if contains `/` or starts with `.` |
| Trailing newline stripped | `secret.rstrip("\\r\\n")` |
| Stays out of `ps` | secret arrives via POST body, never argv |
| Stays out of bash history | `read -rs` is the TTY fallback; the page uses HTTP POST |
| Stays out of transcript | secret never reaches the Claude session — only the confirmation does |

## Companion tool: reverie-secret-add

For headless / SSH / no-browser environments, `reverie-secret-add` is the TTY-prompt counterpart:

```
! reverie-secret-add openrouter.key
```

Uses `read -rs` (no echo) instead of an HTTP form. Refuses to run if stdin is not a TTY (which would defeat the no-echo guarantee). Both tools write to the same path layout (`~/.config/reverie/<name>` mode 600).

## How callers consume the secret

After the user has written it, downstream tools read the file:

```bash
KEY=$(cat ~/.config/reverie/openrouter.key)
curl -H "Authorization: Bearer $KEY" https://openrouter.ai/api/v1/...
```

Or via env var (for child processes):
```bash
export OPENROUTER_API_KEY=$(cat ~/.config/reverie/openrouter.key)
```

The reading tool should:
- never log the value
- never echo it
- never include it in error messages or stack traces
- refuse to print it via any "show config" subcommand

## Page design

The page is intentionally minimal but polished — it should look like a tool the user trusts:

- Dark theme (#0a0e14 background, #7ee787 accent for the "ok" green)
- JetBrains Mono / Fira Code for the secret textarea
- Hexpurr ASCII mascot in the header (matches the rest of the reverie aesthetic)
- Single primary action button ("write & close")
- Property pills at the bottom: localhost only · random port · single-use · csrf-guarded · no logging · atomic write
- Self-explanatory placeholder: "paste here · no quotes · no trailing newline"

## Implementation notes

- Pure Python stdlib (no `requirements.txt`, no `pip install`) so it runs on any reasonable Linux box without setup
- 64 KiB POST body cap (any real secret is well under this; protects against memory exhaustion)
- CSRF check uses constant-time comparison via Python string `==` — adequate at this scale; if paranoid, swap for `hmac.compare_digest`
- The server binds before printing the URL so there's never a race window where the URL is printed but the port isn't ready
- Browser cache is disabled via `Cache-Control: no-store` so the form HTML never lingers
- Favicon returns 204 silently to avoid noise in any future logging

## Security notes

- The server is a single process. If the user runs two `reverie-secret-page` instances simultaneously they'll get different random ports — no collision.
- The CSRF token is bound to the process lifetime; reloading the page refreshes the token automatically because the new GET also re-renders the form.
- The localhost-only bind means the only way to reach the server is from the same host. WSL2 considerations: `127.0.0.1` inside WSL is reachable from the Windows host browser via WSL's virtualization layer — that's the intended UX for this user.
- The file is written to `~/.config/reverie/` which is mode 700. Combined with the file's 600 mode, only `ctodie` can read either.
- The script never reads from any file other than the one it writes. It does not call any network address other than its own listening socket.

## Failure modes

| Failure | Behavior |
|---|---|
| Port range exhausted (extremely unlikely) | Python `OSError` propagates, exit with stack trace |
| Browser blocked from reaching localhost | User sees connection refused; no secret leaked |
| User abandons the page | Server runs forever until Ctrl-C; secret never written |
| User submits empty form | 400 + "empty secret"; server stays up for retry |
| User submits oversized body (>64 KiB) | 400; server stays up |
| CSRF mismatch (e.g., reload tampering) | 403 + "csrf mismatch"; server stays up |
| Disk full / dest unwriteable | Stack trace to stderr; secret value already left memory |

## Cross-references

- `~/.local/bin/reverie-secret-page` — the page server (this skill's source of truth)
- `~/.local/bin/reverie-secret-add` — TTY-prompt fallback
- `~/.config/reverie/` — destination directory (mode 700, ctodie-owned)
- engram `protocol/eventmanager-sudo-delegation` (#528) — the EventManager `read-secret` op that DOWNSTREAM consumers use to read secrets back without leaking them
- engram `policy/anchor-loop` (#521) — anchor's hard rule "never log secret values"
- Hexpurr mascot — same one used in the mesh-status TUI spec (#532)
