#!/usr/bin/env bash
# Regression tests for worktree-jail.sh — encodes the bypasses found in the
# 2026-05-30 harness audit (fail-open set -e abort, git -C / cp-dest escapes,
# flag-after-ref force-push) plus legit in-jail commands that must stay allowed.
# Run: bash claude/hooks/tests/worktree-jail.test.sh
set -uo pipefail

HOOK="${BASH_SOURCE[0]%/*}/../worktree-jail.sh"
JAIL="/home/ctodie/projects/reverie/.claude/worktrees/agent-test"
PARENT="/home/ctodie/projects/reverie"
pass=0 fail=0

# verdict <expect approve|block> <tool> <field-json> <desc>
verdict() {
  local expect="$1" tool="$2" payload="$3" desc="$4"
  local input out got
  input=$(jq -nc --arg cwd "$JAIL" --arg t "$tool" --argjson ti "$payload" \
    '{cwd:$cwd, tool_name:$t, tool_input:$ti}')
  out=$(printf '%s' "$input" | bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"decision":[[:space:]]*"block"'; then got=block
  elif printf '%s' "$out" | grep -q '"approve"'; then got=approve
  else got="ERR(empty/invalid: $out)"; fi
  if [ "$got" = "$expect" ]; then
    pass=$((pass+1)); # printf 'ok   %s\n' "$desc"
  else
    fail=$((fail+1)); printf 'FAIL [%s] expected=%s got=%s\n     %s\n' "$desc" "$expect" "$got" "$payload"
  fi
}
bash_cmd() { verdict "$1" Bash "$(jq -nc --arg c "$2" '{command:$c}')" "$3"; }
edit_fp()  { verdict "$1" Edit "$(jq -nc --arg p "$2" '{file_path:$p}')" "$3"; }

# ── must BLOCK (audit bypasses) ───────────────────────────────────────────────
bash_cmd block "git -C $PARENT reset --hard"                 "git -C parent reset (set-e abort + -C escape)"
bash_cmd block "cp evil.rs $PARENT/src/lib.rs"               "cp into parent (dest escapes)"
bash_cmd block "echo x > $PARENT/src/lib.rs"                 "redirect into parent"
bash_cmd block "cd $PARENT && git reset --hard"              "cd escape"
bash_cmd block "git push --force origin main"                "force-push (flag first)"
bash_cmd block "git push origin main --force"                "force-push (flag after ref)"
bash_cmd block "git push origin +main"                       "force-push (+refspec)"
bash_cmd block "git --git-dir=$PARENT/.git commit -m x"      "git --git-dir redirect"
bash_cmd block "mv ./a $PARENT/b"                            "mv into parent"
bash_cmd block "tee -a $PARENT/x.txt"                        "tee -a into parent"
bash_cmd block "sed -i s/a/b/ $PARENT/Cargo.toml"            "sed -i into parent"
bash_cmd block "cp /jail/a $PARENT/b && echo done"           "cp into parent + chained cmd"
edit_fp  block "$PARENT/src/lib.rs"                          "Edit absolute parent path"

# ── must APPROVE (legit, confined to jail / read-only) ────────────────────────
bash_cmd approve "ls -la"                                    "plain ls (no cd/git/write)"
bash_cmd approve "cargo build --release"                     "cargo build"
bash_cmd approve "git status"                                "git status (non-mutating)"
bash_cmd approve "git commit -m 'wip'"                       "git commit inside jail"
bash_cmd approve "cat $PARENT/README.md"                     "read parent file (no writer)"
bash_cmd approve "cp $PARENT/src/a.rs ./b.rs"                "copy parent→jail (relative dest)"
bash_cmd approve "cp $PARENT/src/a.rs $JAIL/x.rs"            "copy parent→jail (abs dest in jail)"
bash_cmd approve "echo hi > ./out.txt"                       "redirect inside jail"
bash_cmd approve "grep -rn reset $PARENT/docs"               "grep 'reset' in parent (read)"
bash_cmd approve "git -C $PARENT status"                     "git -C parent status (read)"
edit_fp  approve "$JAIL/src/lib.rs"                          "Edit inside jail"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
