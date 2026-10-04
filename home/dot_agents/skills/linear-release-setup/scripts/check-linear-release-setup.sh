#!/usr/bin/env bash
# check-linear-release-setup.sh — audit a repo's linear-release GitHub Actions
# workflows against the estate checklist. Read-only. Exits 1 on any miss.
#
#   ./check-linear-release-setup.sh [repo-root]     # default: $PWD
set -euo pipefail

ROOT="${1:-$PWD}"
WF_DIR="$ROOT/.github/workflows"
shopt -s nullglob
FILES=("$WF_DIR"/linear-release*.yml "$WF_DIR"/linear-release*.yaml)
[ ${#FILES[@]} -gt 0 ] || { echo "no linear-release workflow under $WF_DIR" >&2; exit 1; }

fails=0
check() { # description, 0=ok
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "MISS $desc"; fails=$((fails+1)); fi
}

for f in "${FILES[@]}"; do
  echo "== ${f#"$ROOT"/}"
  check "action pinned by SHA (linear-release-action@<40hex>)" \
    grep -Eq 'linear/linear-release-action@[0-9a-f]{40}' "$f"
  check "checkout pinned by SHA" \
    grep -Eq 'actions/checkout@[0-9a-f]{40}' "$f"
  check "fetch-depth: 0 (full clone for commit scanning)" \
    grep -q 'fetch-depth: 0' "$f"
  check "dormant-until-keyed gate (secret-presence check)" \
    grep -q 'LINEAR_ACCESS_KEY[A-Z_]*:-' "$f"
  check "not tag-triggered (release-please token-created tags never fire push:tags)" \
    sh -c '! grep -Eq "^[[:space:]]+tags:" "$1"' _ "$f"
  check "ubuntu runner (glibc, no musl)" \
    grep -Eq 'runs-on: ubuntu' "$f"
done

if grep -L 'command: complete' "${FILES[@]}" | grep -q 'prod\|linear-release.yml'; then
  echo "MISS prod workflow runs sync WITHOUT complete (release stays in-progress)"
  fails=$((fails+1))
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails checklist miss(es)" >&2; exit 1; fi
echo "all checks passed"
