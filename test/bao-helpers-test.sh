#!/usr/bin/env bash
# Regression test for the OpenBao helpers in home/dot_config/zsh/lib/org.zsh
# (with-bao, bao-whoami, bao-admin). Offline: stub `bao`, a stub token helper and a
# stub admin shell stand in for the real CLI, 1Password and an interactive zsh.
# Invariants: a token never reaches the caller's environment or stdout, and the
# bao-admin token is revoked when its shell exits.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
lib="${1:-$here/home/dot_config/zsh/lib/org.zsh}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.local/bin"

# Token helper: serves the scoped workstation token.
cat > "$tmp/home/.local/bin/bao-token-helper" <<'STUB'
#!/bin/sh
[ "$1" = get ] && printf 'scoped-tok'
STUB

# bao: login prints an admin token; lookup prints JSON that carries the token id;
# revoke -self records which token it revoked.
cat > "$tmp/bin/bao" <<'STUB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "login "*)
    [[ -n "${BAO_TEST_LOGIN_FAIL:-}" ]] && { echo "login failed" >&2; exit 2; }
    printf 'admin-tok' ;;
  "token lookup")
    printf '{"data":{"id":"%s","display_name":"stub-name","policies":["default"],"expire_time":"never","ttl":0}}\n' \
      "${BAO_TOKEN:-scoped-tok}" ;;
  "token revoke")
    printf '%s' "${BAO_TOKEN:-none}" > "$BAO_TEST_DIR/revoked" ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
STUB

# Admin shell: records the token it was given, then exits like a user typing `exit`.
cat > "$tmp/bin/adminshell" <<'STUB'
#!/bin/sh
printf '%s' "${BAO_TOKEN:-none}" > "$BAO_TEST_DIR/shell-token"
STUB
chmod +x "$tmp/bin/bao" "$tmp/bin/adminshell" "$tmp/home/.local/bin/bao-token-helper"

run() {
  # `env` so the optional NAME=VALUE word is an assignment, not a command name.
  env HOME="$tmp/home" PATH="$tmp/bin:$PATH" SHELL="$tmp/bin/adminshell" BAO_TEST_DIR="$tmp" \
    ${2:+BAO_TEST_LOGIN_FAIL=1} zsh -f -c "unset BAO_TOKEN; source '$lib'; $1" 2>/dev/null || true
}

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "ok:   $1"; else echo "FAIL: $1 (got: '$2')"; fail=1; fi
}

check "with-bao gives the command the scoped token" \
  "$(run 'with-bao sh -c "printf %s \"\$BAO_TOKEN\""')" "scoped-tok"
check "with-bao leaves the caller's environment clean" \
  "$(run 'with-bao true; print -r -- "caller=${BAO_TOKEN:-unset}"')" "caller=unset"
check "with-bao with no command is a usage error" \
  "$(run 'with-bao; print -r -- "rc=$?"')" "rc=2"
check "bao-whoami never prints the token id" \
  "$(run 'bao-whoami')" '{"display_name":"stub-name","policies":["default"],"expire_time":"never","ttl":0}'

rm -f "$tmp/shell-token" "$tmp/revoked"
out=$(run 'bao-admin; print -r -- "rc=$? caller=${BAO_TOKEN:-unset}"')
check "bao-admin returns to a clean caller" "$out" "rc=0 caller=unset"
check "bao-admin hands the admin token to its shell" "$(cat "$tmp/shell-token" 2>/dev/null)" "admin-tok"
check "bao-admin revokes the admin token when the shell exits" "$(cat "$tmp/revoked" 2>/dev/null)" "admin-tok"

rm -f "$tmp/shell-token" "$tmp/revoked"
out=$(run 'bao-admin; print -r -- "rc=$?"' loginfail)
check "bao-admin stops when the login fails" "$out" "rc=1"
check "a failed login starts no admin shell" "$([[ -e $tmp/shell-token ]] && echo started || echo none)" "none"

exit $fail
