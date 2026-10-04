#!/usr/bin/env bash
# Regression tests for guard-secret-access.sh — 2026-05-30 audit: native-read
# bypasses ($(<f), mapfile, < redirect, strings), the .env->.environ
# false-positive that blocked ordinary greps, and the Grep empty-path fail-open.
# Exit-code contract: 0 = allow, 2 = block.  Run: bash <this>
set -uo pipefail
# Hooks live under the chezmoi source tree (.chezmoiroot=home), so the test
# targets the source file, not a deployed copy. Resolve from the repo root so
# this works from any cwd and in CI.
_REPO="$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)"
HOOK="${HOOK_OVERRIDE:-$_REPO/home/dot_claude/hooks/executable_guard-secret-access.sh}"
pass=0 fail=0

bash_v() { # <block|allow> <command> <desc>
  local expect="$1" cmd="$2" desc="$3" rc
  printf '%s' "$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')" | bash "$HOOK" >/dev/null 2>&1; rc=$?
  local got=allow; [ "$rc" -eq 2 ] && got=block
  [ "$got" = "$expect" ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL [%s] exp=%s got=%s\n     %s\n' "$desc" "$expect" "$got" "$cmd"; }
}
read_v() { # <block|allow> <path> <desc>
  local expect="$1" p="$2" desc="$3" rc
  printf '%s' "$(jq -nc --arg p "$p" '{tool_name:"Read",tool_input:{file_path:$p}}')" | bash "$HOOK" >/dev/null 2>&1; rc=$?
  local got=allow; [ "$rc" -eq 2 ] && got=block
  [ "$got" = "$expect" ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL [%s] exp=%s got=%s\n     %s\n' "$desc" "$expect" "$got" "$p"; }
}
grep_v() { # <block|allow> <path> <mode> <cwd> <desc>
  local expect="$1" p="$2" mode="$3" cwd="$4" desc="$5" rc
  printf '%s' "$(jq -nc --arg p "$p" --arg m "$mode" --arg c "$cwd" '{tool_name:"Grep",tool_input:({output_mode:$m}+(if $p=="" then {} else {path:$p} end)),cwd:$c}')" | bash "$HOOK" >/dev/null 2>&1; rc=$?
  local got=allow; [ "$rc" -eq 2 ] && got=block
  [ "$got" = "$expect" ] && pass=$((pass+1)) || { fail=$((fail+1)); printf 'FAIL [%s] exp=%s got=%s\n     %s\n' "$desc" "$expect" "$got" "$p $mode $cwd"; }
}

# --- Bash: must BLOCK (reader + secret) ---
bash_v block 'cat ~/.secrets'                       'cat .secrets'
bash_v block 'grep -r KEY ~/.aws/credentials'       'grep aws creds'
bash_v block 'head ~/.ssh/id_rsa'                   'head ssh key'
bash_v block 'strings ~/.ssh/id_ed25519'            'strings ssh key (was missing)'
# --- Bash: native-read bypasses (audit #9) ---
bash_v block 'echo "$(<~/.secrets)"'                '$(<secret) substitution'
bash_v block 'mapfile -t x < ~/.secrets'            'mapfile < secret'
bash_v block 'cat < ~/.secrets'                     '< redirect'
bash_v block 'tr a b < ~/.ssh/id_rsa'               'redirect into tr'
# --- Bash: env dumps ---
bash_v block 'env'                                  'bare env'
bash_v block 'env | sort'                           'env piped'
# --- Bash: must ALLOW (the false-positives + safe forms) ---
bash_v allow "grep -q 'os.environ[\"X\"]' hooks/f.sh" '.environ false-positive (THE bug)'
bash_v allow 'grep -rn environment src/'            'word environment'
bash_v allow '[ -f ~/.secrets ]'                    'presence check'
bash_v allow 'stat -c %s ~/.ssh/id_rsa'             'stat metadata'
bash_v allow 'wc -l ~/.env'                         'wc line count'
bash_v allow 'cat ~/.ssh/id_rsa.pub'                'pubkey (stripped)'
bash_v allow 'cat README.md'                        'non-secret file'
bash_v allow 'grep foo src/lib.rs'                  'grep source'
bash_v allow "env | grep -vE 'KEY|SECRET|TOKEN'"    'env filtered'
bash_v allow 'cat ~/.secrets # allow-secret-read'   'bypass sentinel'
# --- Read tool ---
read_v block '/home/ctodie/.secrets'                'Read secret'
read_v allow '/home/ctodie/.ssh/id_rsa.pub'         'Read pubkey'
read_v allow '/home/ctodie/projects/x/README.md'    'Read normal'
# --- Grep tool ---
grep_v block '/home/ctodie/.aws/credentials' content '' 'Grep content on secret'
grep_v allow '/home/ctodie/.aws/credentials' files_with_matches '' 'Grep files-mode on secret (presence)'
grep_v block '' content '/home/ctodie/.config/op'   'Grep content, empty path, secret cwd (#22)'
grep_v allow '' content '/home/ctodie/projects/x'   'Grep content, empty path, normal cwd'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
