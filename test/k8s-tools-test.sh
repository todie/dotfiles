#!/usr/bin/env bash
# k8s-tools-test.sh — offline, deterministic regression tests for the k8s-tools
# bootstrap (home/run_once_after_25-k8s-tools.sh.tmpl). No network: the
# download+verify+extract+install path is driven through `file://` URLs against
# locally-built fixtures, so it runs in CI and never hits GitHub.
#
# Covers exactly the branches the manual smoke test could NOT (binaries were
# already present, so the install path was skipped):
#   1. happy path     — correct checksum → binary installed + executable
#   2. checksum reject — wrong checksum → returns non-zero AND installs nothing
#   3. missing member  — requested binary absent from tarball → non-zero
#   4. lock-step       — completions.zsh _COMPLETION_GEN tool set == the
#                        run_once_after_30 pre-warmer spec set (the documented
#                        "keep in lock-step" invariant)
#
# Run:  bash test/k8s-tools-test.sh    (exit code = number of failed checks)

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || cd "$(dirname "$0")/.."
ROOT=$(pwd)

RED=$'\e[31m'; GRN=$'\e[32m'; NC=$'\e[0m'; [[ -t 1 ]] || { RED=; GRN=; NC=; }
fail=0
ok()  { echo "${GRN}✓${NC} $1"; }
bad() { echo "${RED}✗${NC} $1"; fail=$((fail+1)); }

BOOT="home/run_once_after_25-k8s-tools.sh.tmpl"

# ── source the bootstrap as a library (functions only) ───────────────────────
render=$(mktemp)
if grep -q '{{' "$BOOT"; then
  if command -v chezmoi >/dev/null 2>&1; then chezmoi execute-template < "$BOOT" > "$render"
  else echo "SKIP: $BOOT has template directives and chezmoi is absent"; exit 0; fi
else
  cp "$BOOT" "$render"
fi
# shellcheck disable=SC1090
_srcbin=$(mktemp -d)   # throwaway; each test below resets BIN anyway
ARCH=amd64 BIN="$_srcbin" K8S_TOOLS_SOURCE_ONLY=1 source "$render"
if declare -F _fetch_verify_install >/dev/null; then ok "sourced _fetch_verify_install"; else bad "could not source _fetch_verify_install"; echo "fatal"; exit 1; fi

# ── build offline fixtures ───────────────────────────────────────────────────
fix=$(mktemp -d)
printf '#!/bin/sh\necho faketool 1.0\n' > "$fix/faketool"; chmod +x "$fix/faketool"
( cd "$fix" && tar -czf faketool.tgz faketool )
good_sum=$(sha256sum "$fix/faketool.tgz" | awk '{print $1}')
printf '%s  faketool.tgz\n' "$good_sum"                         > "$fix/good.txt"
printf '%s  faketool.tgz\n' "0000000000000000000000000000000000000000000000000000000000000000" > "$fix/bad.txt"

# 1. happy path
BIN=$(mktemp -d)
_fetch_verify_install faketool "file://$fix/faketool.tgz" "file://$fix/good.txt" faketool >/dev/null 2>&1
if [[ -x "$BIN/faketool" ]]; then ok "happy path: binary installed + executable"; else bad "happy path: binary not installed"; fi
rm -rf "$BIN"

# 2. checksum mismatch → must reject and install nothing
BIN=$(mktemp -d)
if _fetch_verify_install faketool "file://$fix/faketool.tgz" "file://$fix/bad.txt" faketool >/dev/null 2>&1; then
  bad "checksum reject: returned success on bad sum"
else ok "checksum reject: returned non-zero on bad sum"; fi
if [[ -e "$BIN/faketool" ]]; then bad "checksum reject: installed despite bad sum"; else ok "checksum reject: installed nothing"; fi
rm -rf "$BIN"

# 3. requested member absent from tarball → non-zero
BIN=$(mktemp -d)
if _fetch_verify_install faketool "file://$fix/faketool.tgz" "file://$fix/good.txt" not-in-tarball >/dev/null 2>&1; then
  bad "missing member: returned success"
else ok "missing member: returned non-zero"; fi
rm -rf "$BIN"

# 4. lock-step: completions.zsh _COMPLETION_GEN  ==  run_once_after_30 specs.
# Parse ONLY inside each array block (…=( … )) so function calls/comments
# elsewhere in the files don't leak in.
gen=$(awk '/_COMPLETION_GEN=\(/{f=1;next} f&&/^\)/{f=0} f' home/dot_config/zsh/lib/completions.zsh \
        | grep -E '^[[:space:]]+_' | awk '{print $1}' | sort -u)
pre=$(awk '/specs=\(/{f=1;next} f&&/^\)/{f=0} f' home/run_once_after_30-zsh-completions.sh.tmpl \
        | grep -oE '"_[a-z0-9_-]+' | tr -d '"' | sort -u)
if [[ "$gen" == "$pre" ]]; then
  ok "lock-step: completions.zsh and run_once pre-warmer list the same tools ($(echo "$gen" | wc -l) entries)"
else
  bad "lock-step DRIFT between completions.zsh and run_once pre-warmer:"
  diff <(echo "$gen") <(echo "$pre") | sed 's/^/    /'
fi

rm -rf "$fix" "$render" "$_srcbin"
echo "── k8s-tools tests: $fail failed ──"
exit "$fail"
