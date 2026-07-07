#!/usr/bin/env bash
# k8s-tools-e2e.sh — END-TO-END check of the pinned kubecolor external:
# renders .chezmoiexternal.toml.tmpl, downloads the ACTUAL release URL,
# sha256-verifies against the rendered pin, extracts, and asserts the binary
# reports the pinned version. Throwaway dir — never touches ~/.local/bin.
#
# NETWORK-DEPENDENT and rate-limit-prone → deliberately NOT in CI. Run locally
# after bumping the pin in .chezmoiexternal.toml.tmpl, or on a nightly:
#     bash test/k8s-tools-e2e.sh
#
# Exit code = number of failed checks.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || cd "$(dirname "$0")/.."

RED=$'\e[31m'; GRN=$'\e[32m'; NC=$'\e[0m'; [[ -t 1 ]] || { RED=; GRN=; NC=; }
fail=0
ok()  { echo "${GRN}✓${NC} $1"; }
bad() { echo "${RED}✗${NC} $1"; fail=$((fail+1)); }

command -v chezmoi >/dev/null 2>&1 || { echo "SKIP: chezmoi absent"; exit 0; }

render=$(mktemp)
chezmoi execute-template < home/.chezmoiexternal.toml.tmpl > "$render"
url=$(grep -E '^\s*url = ' "$render" | head -1 | sed 's/.*url = "\(.*\)"/\1/')
want=$(grep -E '^\s*checksum\.sha256 = ' "$render" | head -1 | sed 's/.*= "\([0-9a-f]*\)"/\1/')
ver=$(echo "$url" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d v)
[[ -n "$url" && -n "$want" && -n "$ver" ]] || { bad "could not parse url/checksum/version from rendered external"; exit 1; }

tmp=$(mktemp -d)
if ! curl -fsSL "$url" -o "$tmp/pkg.tgz"; then
  bad "download failed: $url"
else
  got=$(sha256sum "$tmp/pkg.tgz" | awk '{print $1}')
  if [[ "$got" == "$want" ]]; then ok "sha256 matches rendered pin"; else bad "sha256 MISMATCH (want=$want got=$got) — fix the pin"; fi
  tar -xzf "$tmp/pkg.tgz" -C "$tmp" 2>/dev/null || true
  bin=$(find "$tmp" -type f -name kubecolor | head -1)
  if [[ -n "$bin" ]] && chmod +x "$bin" && "$bin" --kubecolor-version 2>/dev/null | grep -q "$ver"; then
    ok "kubecolor $ver extracted + reports pinned version"
  else bad "kubecolor version check failed"; fi
fi

# Guard: only ever remove a /tmp throwaway dir.
case "$tmp" in /tmp/*|"${TMPDIR:-/nonexistent}"/*) rm -rf "$tmp" ;; *) echo "refusing to rm non-temp $tmp" >&2 ;; esac
rm -f "$render"
echo "── k8s-tools e2e: $fail failed ──"
exit "$fail"
