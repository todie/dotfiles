#!/usr/bin/env bash
# Regression tests for role-boundary-gate.sh — encodes the 2026-05-30 audit:
# obsolete .tool/.input.file_path fields (gate was a dead no-op) and the
# docs/../../.ssh traversal bypass. allow = exit 0 no deny; deny = hook_deny.
# Run: bash <this>
set -uo pipefail
HOOK="${BASH_SOURCE[0]%/*}/../role-boundary-gate.sh"
R="/home/ctodie/projects/reverie"   # a real git repo, so rel_path resolves
pass=0 fail=0

# v <allow|deny> <role> <tool> <path> <desc>
v() {
  local expect="$1" role="$2" tool="$3" path="$4" desc="$5" out got
  out=$(printf '%s' "$(jq -nc --arg t "$tool" --arg p "$path" '{tool_name:$t, tool_input:{file_path:$p}}')" \
        | REVERIE_MESH_ROLE="$role" bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then got=deny; else got=allow; fi
  if [ "$got" = "$expect" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); printf 'FAIL [%s] role=%s expected=%s got=%s\n     %s\n' "$desc" "$role" "$expect" "$got" "$path"
  fi
}

# memory → docs/ + CHANGELOG only
v allow memory Edit "$R/docs/note.md"            'memory: docs allowed'
v allow memory Edit "$R/CHANGELOG.md"            'memory: CHANGELOG allowed'
v deny  memory Edit "$R/src/lib.rs"              'memory: src denied'
v deny  memory Edit "$R/docs/../../.ssh/authorized_keys" 'memory: .. traversal to .ssh denied'
v deny  memory Edit "$R/docs/../crates/x/lib.rs" 'memory: .. traversal to crates denied'
v deny  memory MultiEdit "$R/src/lib.rs"         'memory: MultiEdit src denied'
# research → docs/research only
v allow research Edit "$R/docs/research/r.md"    'research: docs/research allowed'
v deny  research Edit "$R/docs/other.md"         'research: docs/other denied'
# security → docs/security + Cargo.lock
v allow security Edit "$R/docs/security/s.md"    'security: docs/security allowed'
v allow security Edit "$R/Cargo.lock"            'security: Cargo.lock allowed'
v deny  security Edit "$R/src/main.rs"           'security: src denied'
# anchor / builder / unset → unrestricted
v allow anchor  Edit "$R/src/anything.rs"        'anchor: unrestricted'
v allow builder Edit "$R/src/anything.rs"        'builder: unrestricted'
v allow ''      Edit "$R/src/anything.rs"        'no role: passthrough'
# non-mutating tool → passthrough
v allow memory Read "$R/src/lib.rs"              'memory: Read passthrough'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
