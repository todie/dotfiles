#!/usr/bin/env bash
# SessionStart hook — active nudge for loop discipline + presentation/decisions
# (see ~/.claude/rules/loop-discipline.md and rules/presentation-and-decisions.md).
# Prints to stderr so it surfaces without coupling to any SessionStart JSON
# contract. Exits 0 unconditionally — never blocks.
set +e
cat >&2 <<'EOF'
loop-discipline ▸ before substantive work, get the brief: landscape · constraints · goal
              ▸ one thread to DONE before the next; park deferred work (Linear/memory), don't drop it
              ▸ new power (tokens/scopes/batches/apply)? name the blast radius + guardrail first
              ▸ irreversible / outward actions (merge, apply, rotate, external send) = operator approves
interview      ▸ open decisions (any fork that changes what you do next) = AskUserQuestion, not a wall of prose
              ▸ long-form to judge (>~40 lines: plans, RFCs, proposals) = write to file + $EDITOR; chat gets a short orientation
research-team  ▸ fanning out research agents? batch MCP/Linear reads ONCE → shared read-surfaces (/tmp/research-surfaces/) → forbid per-agent re-fetch
              ▸ see ~/.claude/rules/research-team-discipline.md
EOF
exit 0
