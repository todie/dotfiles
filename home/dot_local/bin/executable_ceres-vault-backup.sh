#!/usr/bin/env bash
# ceres-vault-backup.sh — age-encrypted snapshot of ceres dotfiles + estate docs → R2.
#
# Crypto boundary: the tar NEVER touches disk or the network unencrypted. It is
# piped straight into `age` and only the ciphertext is written out.
#
# Recovery key: age identity escrowed in 1Password as document
# "ceres-vault-age-identity" (vault: cloud). The private key is NOT on this
# machine by design — losing ceres must not lose the ability to decrypt.
#   Restore:  op document get "ceres-vault-age-identity" --vault cloud --out-file /tmp/k
#             rclone cat r2:ceres-vault/<object> | age -d -i /tmp/k | tar -tzf -
#
# Usage: ceres-vault-backup.sh [--prune N] [--dry-run]
#   --prune N   after a successful upload, delete all but the newest N snapshots
#               (default: no pruning — deletions are never implicit)
set -euo pipefail

RECIPIENT_FILE="${VAULT_RECIPIENT:-$HOME/.config/age/ceres-vault.pub}"
REMOTE="${VAULT_REMOTE:-r2:ceres-vault}"
PRUNE_KEEP=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prune) PRUNE_KEEP="${2:?--prune needs a count}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Paths are relative to $HOME. Selected 2026-07-21: config + irreplaceable work
# + private key material. Deliberately EXCLUDES ~/.claude (4.3G, mostly
# disposable session transcripts) and ~/.kube (regenerable from Terraform).
PATHS=(
  ".agents"           # SOPs binding every harness — unversioned
  ".config/sops"      # SOPS age keys
  ".gam"              # Google Workspace OAuth
  ".ssh"              # SSH private keys
  ".gnupg"            # GPG signing key 29234C4D7EE749F2
  "vesperan-estate"   # estate inventory/valuation — unversioned, irreplaceable
  "todo.md"           # operator punch list
)

[ -f "$RECIPIENT_FILE" ] || { echo "FATAL: no recipient at $RECIPIENT_FILE" >&2; exit 1; }
command -v age >/dev/null || { echo "FATAL: age not on PATH" >&2; exit 1; }
command -v rclone >/dev/null || { echo "FATAL: rclone not on PATH" >&2; exit 1; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME="ceres-vault-${STAMP}.tar.gz.age"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
umask 077

present=(); missing=()
for p in "${PATHS[@]}"; do
  if [ -e "$HOME/$p" ]; then present+=("$p"); else missing+=("$p"); fi
done
# Never silently drop a requested path.
[ ${#missing[@]} -gt 0 ] && printf 'WARNING: not present, excluded from snapshot: %s\n' "${missing[*]}" >&2
[ ${#present[@]} -gt 0 ] || { echo "FATAL: nothing to back up" >&2; exit 1; }

echo "== snapshot $NAME =="
echo "   including: ${present[*]}"

if [ "$DRY_RUN" = 1 ]; then echo "   (dry run — nothing written)"; exit 0; fi

# Sockets (gpg-agent) and caches are not archivable / not wanted.
# tar exits 1 on "file changed as we read it"; tolerate 0 and 1, fail on >1.
set +e
tar -C "$HOME" \
    --exclude='S.*' --exclude='*.sock' --exclude='*/.cache/*' \
    --warning=no-file-ignored --warning=no-file-changed \
    -czf - "${present[@]}" 2>"$WORK/tar.err" \
  | age -R "$RECIPIENT_FILE" -o "$WORK/$NAME"
# Capture the WHOLE array in one assignment — reading PIPESTATUS[0] into a
# variable is itself a command and resets PIPESTATUS before index 1 is read.
ps=("${PIPESTATUS[@]}")
rc=${ps[0]}; age_rc=${ps[1]}
set -e
[ "$age_rc" -eq 0 ] || { echo "FATAL: age encryption failed" >&2; cat "$WORK/tar.err" >&2; exit 1; }
[ "$rc" -le 1 ] || { echo "FATAL: tar failed (rc=$rc)" >&2; cat "$WORK/tar.err" >&2; exit 1; }
[ -s "$WORK/$NAME" ] || { echo "FATAL: empty ciphertext" >&2; exit 1; }

SUM=$(sha256sum "$WORK/$NAME" | awk '{print $1}')
SIZE=$(stat -c %s "$WORK/$NAME")
echo "   ciphertext: $SIZE bytes  sha256:${SUM:0:16}…"

# Refuse to upload anything that is not actually age ciphertext.
head -c 22 "$WORK/$NAME" | grep -q 'age-encryption.org' \
  || { echo "FATAL: output is not age ciphertext — refusing to upload" >&2; exit 1; }

printf '%s  %s\n%s bytes\nhost=%s\npaths=%s\n' \
  "$SUM" "$NAME" "$SIZE" "$(hostname)" "${present[*]}" > "$WORK/$NAME.sha256"

rclone copyto "$WORK/$NAME" "$REMOTE/$NAME" --s3-no-check-bucket 2>&1 | tail -2
rclone copyto "$WORK/$NAME.sha256" "$REMOTE/$NAME.sha256" --s3-no-check-bucket 2>&1 | tail -1

# Verify the uploaded object by re-reading it, not by trusting the writer.
REMOTE_SUM=$(rclone cat "$REMOTE/$NAME" | sha256sum | awk '{print $1}')
if [ "$REMOTE_SUM" = "$SUM" ]; then
  echo "   UPLOAD VERIFIED — remote sha256 matches local"
else
  echo "FATAL: remote checksum mismatch (local=$SUM remote=$REMOTE_SUM)" >&2; exit 1
fi

if [ -n "$PRUNE_KEEP" ]; then
  echo "== prune: keeping newest $PRUNE_KEEP =="
  mapfile -t old < <(rclone lsf "$REMOTE" --include 'ceres-vault-*.tar.gz.age' \
                     | sort -r | tail -n +$((PRUNE_KEEP+1)))
  if [ ${#old[@]} -eq 0 ]; then
    echo "   nothing to prune"
  else
    for o in "${old[@]}"; do
      echo "   deleting $o"
      rclone deletefile "$REMOTE/$o"
      rclone deletefile "$REMOTE/$o.sha256" 2>/dev/null || true
    done
  fi
fi

echo "== done: $REMOTE/$NAME =="
