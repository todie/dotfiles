#!/usr/bin/env bash
# k8s-tools-test.sh — offline, deterministic regression tests for the k8s-tools
# surface. The binary install path moved to .chezmoiexternal.toml.tmpl
# (chezmoi-native pinned fetch + sha256); what remains testable offline:
#   1. external render — .chezmoiexternal.toml.tmpl renders with a pinned
#      version in the URL and a 64-hex sha256 (the pin-everything invariant)
#   2. shim library     — the run_once script still sources as a library and
#      exposes _gen_completion_shims
#   3. lock-step        — completions.zsh _COMPLETION_GEN tool set == the
#                         run_once_after_30 pre-warmer spec set (the documented
#                         "keep in lock-step" invariant)
#
# Run:  bash test/k8s-tools-test.sh    (exit code = number of failed checks)

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || cd "$(dirname "$0")/.."
ROOT=$(pwd)

RED=$'\e[31m'; GRN=$'\e[32m'; NC=$'\e[0m'; [[ -t 1 ]] || { RED=; GRN=; NC=; }
fail=0
ok()  { echo "${GRN}✓${NC} $1"; }
bad() { echo "${RED}✗${NC} $1"; fail=$((fail+1)); }

command -v chezmoi >/dev/null 2>&1 || { echo "SKIP: chezmoi absent"; exit 0; }

# 1. external render: pinned URL + sha256 present and well-formed
EXT="home/.chezmoiexternal.toml.tmpl"
render=$(mktemp)
chezmoi execute-template < "$EXT" > "$render" 2>/dev/null
if grep -qE 'url = "https://github\.com/kubecolor/kubecolor/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/' "$render"; then
  ok "external: kubecolor URL carries a pinned version"
else bad "external: no pinned version in kubecolor URL"; fi
if grep -qE 'checksum\.sha256 = "[0-9a-f]{64}"' "$render"; then
  ok "external: sha256 checksum present (64-hex)"
else bad "external: checksum missing or malformed"; fi
rm -f "$render"

# 2. shim library sources cleanly
BOOT="home/run_once_after_25-k8s-tools.sh.tmpl"
render=$(mktemp)
if grep -q '{{' "$BOOT"; then chezmoi execute-template < "$BOOT" > "$render"; else cp "$BOOT" "$render"; fi
_srcbin=$(mktemp -d)
# shellcheck disable=SC1090
BIN="$_srcbin" K8S_TOOLS_SOURCE_ONLY=1 source "$render"
if declare -F _gen_completion_shims >/dev/null; then ok "sourced _gen_completion_shims"; else bad "could not source _gen_completion_shims"; fi
rm -rf "$render" "$_srcbin"

# 3. lock-step: completions.zsh _COMPLETION_GEN  ==  run_once_after_30 specs.
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

echo "── k8s-tools tests: $fail failed ──"
exit "$fail"
