#!/usr/bin/env bash
# SessionStart hook — active nudge for loop discipline (see ~/.claude/rules/
# loop-discipline.md). Prints to stderr so it surfaces without coupling to any
# SessionStart JSON contract. Exits 0 unconditionally — never blocks.
set +e
cat >&2 <<'EOF'
loop-discipline ▸ before substantive work, get the brief: landscape · constraints · goal
              ▸ one thread to DONE before the next; park deferred work (Linear/memory), don't drop it
              ▸ new power (tokens/scopes/batches/apply)? name the blast radius + guardrail first
              ▸ irreversible / outward actions (merge, apply, rotate, external send) = operator approves
EOF
exit 0
