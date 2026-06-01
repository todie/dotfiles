#!/usr/bin/env bash
# k8s-tools-e2e.sh — END-TO-END check of the real fresh-machine install path:
# downloads the ACTUAL pinned releases from GitHub, sha256-verifies, extracts,
# and asserts each reports its pinned version. Installs into a throwaway dir —
# never touches your real ~/.local/bin.
#
# NETWORK-DEPENDENT and rate-limit-prone → deliberately NOT in CI. Run locally
# after bumping a pinned version, or on a nightly:
#     bash test/k8s-tools-e2e.sh
#
# Exit code = number of failed checks.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || cd "$(dirname "$0")/.."

RED=$'\e[31m'; GRN=$'\e[32m'; NC=$'\e[0m'; [[ -t 1 ]] || { RED=; GRN=; NC=; }
fail=0
ok()  { echo "${GRN}✓${NC} $1"; }
bad() { echo "${RED}✗${NC} $1"; fail=$((fail+1)); }

case "$(uname -m)" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "unsupported arch"; exit 0 ;; esac
export ARCH

BOOT="home/run_once_after_25-k8s-tools.sh.tmpl"
render=$(mktemp)
if grep -q '{{' "$BOOT" && command -v chezmoi >/dev/null 2>&1; then chezmoi execute-template < "$BOOT" > "$render"; else cp "$BOOT" "$render"; fi
# Set BIN AFTER sourcing — the bootstrap now honors a pre-set $BIN, but ordering
# this way is belt-and-suspenders so a throwaway dir is always what we clean up.
# shellcheck disable=SC1090
K8S_TOOLS_SOURCE_ONLY=1 source "$render"
BIN=$(mktemp -d)

# Force a real download of the pinned kubecolor release into the throwaway BIN.
# (stern + kustomize moved to the mise manifest; only kubecolor lives on this
# installer now, so this is the only tool the e2e exercises.)
_fetch_verify_install kubecolor \
  "https://github.com/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VER}/kubecolor_${KUBECOLOR_VER}_linux_${ARCH}.tar.gz" \
  "https://github.com/kubecolor/kubecolor/releases/download/v${KUBECOLOR_VER}/checksums.txt" kubecolor >/dev/null 2>&1

"$BIN/kubecolor" --kubecolor-version 2>/dev/null | grep -q "$KUBECOLOR_VER"  && ok "kubecolor $KUBECOLOR_VER installed + verified" || bad "kubecolor install/verify failed"

# Guard: only ever remove a /tmp throwaway dir — never ~/.local/bin etc.
case "$BIN" in /tmp/*|"$TMPDIR"/*) rm -rf "$BIN" ;; *) echo "refusing to rm non-temp BIN=$BIN" >&2 ;; esac
rm -f "$render"
echo "── k8s-tools e2e: $fail failed ──"
exit "$fail"
