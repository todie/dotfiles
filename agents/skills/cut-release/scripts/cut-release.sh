#!/usr/bin/env bash
# cut-release.sh — bundle the "prepare a release" workflow into one command.
#
# Bumps the canonical version source, updates Helm chart if present, rolls
# CHANGELOG.md, commits, and tags. Stops short of pushing.
#
# Usage:
#   cut-release.sh patch     # 0.1.0 -> 0.1.1
#   cut-release.sh minor     # 0.1.0 -> 0.2.0
#   cut-release.sh major     # 0.1.0 -> 1.0.0
#   cut-release.sh 0.2.0     # explicit
#   cut-release.sh patch --dry-run
#   cut-release.sh patch --skip-security          # TOD-742 emergency bypass
#   cut-release.sh patch --security-timeout=600   # TOD-742 custom wait (default 1800)

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
DRY_RUN=0
SKIP_SECURITY=0
SECURITY_TIMEOUT=1800
BUMP=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --skip-security) SKIP_SECURITY=1 ;;
        --security-timeout=*) SECURITY_TIMEOUT="${arg#--security-timeout=}" ;;
        -h|--help)
            sed -n "2,14p" "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) BUMP="$arg" ;;
    esac
done

if [ -z "$BUMP" ]; then
    echo "usage: cut-release.sh <patch|minor|major|VERSION> [--dry-run]" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
cd "$(git rev-parse --show-toplevel)"

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

note() { printf "==> %s\n" "$*"; }
warn() { printf "    warn: %s\n" "$*" >&2; }
die()  { printf "ERROR: %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Detect canonical version source
# ---------------------------------------------------------------------------
CURRENT=""
SOURCE=""

if [ -f VERSION ]; then
    CURRENT=$(tr -d '[:space:]' < VERSION)
    SOURCE="VERSION"
elif [ -f Cargo.toml ] && grep -q '^\[workspace.package\]' Cargo.toml; then
    CURRENT=$(awk '/^\[workspace.package\]/{f=1; next} /^\[/{f=0} f && /^version[[:space:]]*=/' Cargo.toml | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    SOURCE="Cargo.toml (workspace.package)"
elif [ -f Cargo.toml ] && grep -q '^\[package\]' Cargo.toml; then
    CURRENT=$(awk '/^\[package\]/{f=1; next} /^\[/{f=0} f && /^version[[:space:]]*=/' Cargo.toml | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    SOURCE="Cargo.toml (package)"
elif [ -f package.json ]; then
    CURRENT=$(python3 -c "import json; print(json.load(open('package.json'))['version'])")
    SOURCE="package.json"
elif [ -f pyproject.toml ]; then
    CURRENT=$(awk '/^\[(project|tool\.poetry)\]/{f=1; next} /^\[/{f=0} f && /^version[[:space:]]*=/' pyproject.toml | head -1 | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/')
    SOURCE="pyproject.toml"
fi

if [ -z "$CURRENT" ] || [ -z "$SOURCE" ]; then
    die "no canonical version source found (looked for: VERSION, Cargo.toml, package.json, pyproject.toml)"
fi

note "current version: $CURRENT  (source: $SOURCE)"

# ---------------------------------------------------------------------------
# Compute new version
# ---------------------------------------------------------------------------
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$BUMP" in
    patch) NEW="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) NEW="$MAJOR.$((MINOR + 1)).0" ;;
    major) NEW="$((MAJOR + 1)).0.0" ;;
    *)
        if ! [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-].*)?$ ]]; then
            die "invalid version: '$BUMP' (expected patch|minor|major or semver)"
        fi
        NEW="$BUMP"
        ;;
esac

# Strict-greater check
python3 -c "
import sys
def parse(v): return tuple(int(p) for p in v.split('-')[0].split('+')[0].split('.'))
if parse('$NEW') <= parse('$CURRENT'):
    print('not strictly greater', file=sys.stderr)
    sys.exit(1)
" || die "new version ($NEW) is not strictly greater than current ($CURRENT)"

note "new version: $NEW"

# ---------------------------------------------------------------------------
# Working tree check
# ---------------------------------------------------------------------------
DIRTY_OTHER=$(git status --porcelain | grep -v -E "^.M (VERSION|Cargo\.toml|Cargo\.lock|package\.json|package-lock\.json|pyproject\.toml|helm/Chart\.yaml|CHANGELOG\.md)$" || true)
if [ -n "$DIRTY_OTHER" ]; then
    warn "working tree has uncommitted non-version changes:"
    echo "$DIRTY_OTHER" | sed 's/^/      /' >&2
    die "commit or stash other changes first"
fi

# ---------------------------------------------------------------------------
# CHANGELOG check
# ---------------------------------------------------------------------------
[ -f CHANGELOG.md ] || die "no CHANGELOG.md — create one first (see global feedback_always_changelog)"

if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    die "CHANGELOG.md has no [Unreleased] section"
fi

UNRELEASED_BODY=$(awk '/^## \[Unreleased\]/{f=1; next} f && /^## /{exit} f' CHANGELOG.md | grep -v '^[[:space:]]*$' | head -1)
if [ -z "$UNRELEASED_BODY" ]; then
    die "CHANGELOG.md [Unreleased] section is empty — nothing to release"
fi

# ---------------------------------------------------------------------------
# Detect GitHub remote for compare links
# ---------------------------------------------------------------------------
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
GH_REPO=""
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    GH_REPO="${BASH_REMATCH[1]}"
    note "github repo: $GH_REPO"
else
    warn "could not detect GitHub repo from origin remote (compare links will be skipped)"
fi

# ---------------------------------------------------------------------------
# Apply changes
# ---------------------------------------------------------------------------
note "updating $SOURCE"
case "$SOURCE" in
    "VERSION") run sh -c "echo '$NEW' > VERSION" ;;
    Cargo.toml*) run sh -c "sed -i -E '0,/^version[[:space:]]*=[[:space:]]*\"[^\"]*\"/{s//version = \"$NEW\"/}' Cargo.toml" ;;
    "package.json") run python3 -c "
import json
d = json.load(open('package.json'))
d['version'] = '$NEW'
open('package.json', 'w').write(json.dumps(d, indent=2) + '\n')
" ;;
    "pyproject.toml") run sh -c "sed -i -E '0,/^version[[:space:]]*=[[:space:]]*\"[^\"]*\"/{s//version = \"$NEW\"/}' pyproject.toml" ;;
esac

if [ -f helm/Chart.yaml ]; then
    note "updating helm/Chart.yaml"
    run sed -i "s/^version:.*/version: $NEW/" helm/Chart.yaml
    run sed -i "s/^appVersion:.*/appVersion: \"$NEW\"/" helm/Chart.yaml
fi

note "rolling CHANGELOG.md"
DATE=$(date +%Y-%m-%d)
run python3 - << PYEOF
import re
from pathlib import Path

new = "$NEW"
current = "$CURRENT"
date = "$DATE"
gh_repo = "$GH_REPO"

p = Path("CHANGELOG.md")
text = p.read_text()

# Roll [Unreleased] -> [Unreleased] + new dated section header
text = re.sub(
    r'^## \[Unreleased\]\s*$',
    f'## [Unreleased]\n\n## [{new}] - {date}',
    text,
    count=1,
    flags=re.MULTILINE,
)

# Update compare links at the bottom
if gh_repo:
    base = f"https://github.com/{gh_repo}"
    text = re.sub(
        r'^\[Unreleased\]:.*$',
        f'[Unreleased]: {base}/compare/v{new}...HEAD\n[{new}]: {base}/compare/v{current}...v{new}',
        text,
        count=1,
        flags=re.MULTILINE,
    )

p.write_text(text)
PYEOF

# ---------------------------------------------------------------------------
# Commit and tag
# ---------------------------------------------------------------------------
note "committing"
STAGE_FILES=()
for f in VERSION Cargo.toml Cargo.lock package.json package-lock.json pyproject.toml helm/Chart.yaml CHANGELOG.md; do
    [ -f "$f" ] && STAGE_FILES+=("$f")
done
run git add "${STAGE_FILES[@]}"
run git commit -m "Release v$NEW"

# ---------------------------------------------------------------------------
# Security gate (TOD-742)
# ---------------------------------------------------------------------------
# Look for a coord-wait-security-ok helper in the current repo's scripts/
# (ships with reverie). If present, block until security role sends
# `security-ok v$NEW` or --skip-security was passed. Absent helper = skip
# silently (non-reverie repos don't have the mesh).
WAIT_HELPER="scripts/coord-wait-security-ok"
if [ -x "$WAIT_HELPER" ]; then
    if [ "$SKIP_SECURITY" = "1" ]; then
        note "security gate SKIPPED (--skip-security) — audit trail written"
        run "$WAIT_HELPER" "v$NEW" --skip-security
    else
        note "waiting for security-ok v$NEW (timeout ${SECURITY_TIMEOUT}s) — send from security role:"
        note "  coord send \$(coord whoami | jq -r .session_id) security-ok v$NEW --body <scan-summary>"
        if [ "$DRY_RUN" = "0" ]; then
            "$WAIT_HELPER" "v$NEW" --timeout "$SECURITY_TIMEOUT" || {
                echo "ERROR: security gate blocked — no security-ok v$NEW received" >&2
                echo "  retry with --skip-security for emergency override (audit-logged)" >&2
                exit 1
            }
        fi
    fi
fi

note "tagging v$NEW"
run git tag -a "v$NEW" -m "Release v$NEW"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
note "Release v$NEW prepared (not pushed)"
echo
echo "    Push:"
echo "      git push origin HEAD --tags"
[ -n "$GH_REPO" ] && echo "      gh release create v$NEW --generate-notes"
echo
echo "    Undo:"
echo "      git reset --soft HEAD~1 && git tag -d v$NEW"
