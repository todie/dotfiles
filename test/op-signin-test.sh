#!/usr/bin/env bash
# Regression test for the `op signin` wrapper in home/dot_config/zsh/lib/secrets.zsh.
# With OP_SERVICE_ACCOUNT_TOKEN in the environment (sourced from ~/.secrets), a
# personal `op signin` must still work. A stub `op` stands in for the real CLI:
# like 1Password's, its signin refuses while the service-account token is set.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
lib="${1:-$here/home/dot_config/zsh/lib/secrets.zsh}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"

cat > "$tmp/bin/op" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  signin)
    # Refuses while the service-account token is set, or while an expired
    # personal session is still exported (suspected cause, 2026-10-27).
    if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" || "${OP_SESSION_test:-}" == stale ]]; then
      echo "[ERROR] You are not currently signed in" >&2
      exit 1
    fi
    echo 'export OP_SESSION_test="personal"' ;;
  whoami) echo "whoami" ;;
  *) echo "passthrough $* token=${OP_SERVICE_ACCOUNT_TOKEN:+set}" ;;
esac
STUB
chmod +x "$tmp/bin/op"

run() {
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" OP_SERVICE_ACCOUNT_TOKEN=sa OP_SESSION_test="${2:-}" \
    zsh -f -c "[[ -z \$OP_SESSION_test ]] && unset OP_SESSION_test; source '$lib'; $1" 2>/dev/null || true
}
state='print -r -- "token=${OP_SERVICE_ACCOUNT_TOKEN:+set} session=${OP_SESSION_test:-none}"'

fail=0
check() {
  if [[ "$2" == "$3" ]]; then echo "ok:   $1"; else echo "FAIL: $1 (got: '$2')"; fail=1; fi
}

check "op signin in this shell" "$(run "op signin >/dev/null; $state")" "token= session=personal"
check 'eval "$(op signin)"' "$(run "eval \"\$(op signin)\"; $state")" "token= session=personal"
check "op signin with a stale session exported" "$(run "op signin >/dev/null; $state" stale)" "token= session=personal"
check "other subcommands pass through with the token" "$(run 'op read op://v/i/f')" "passthrough read op://v/i/f token=set"

exit $fail
