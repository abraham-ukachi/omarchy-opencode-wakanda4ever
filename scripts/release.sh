#!/usr/bin/env bash

##############################
# Name: Wakanda4Ever - Release Helper
# Script: release.sh
# Author: Abraham Ukachi <abrahamukachi@gmail.com>
#
# Usage:
#   1-|> bash scripts/release.sh          (auto-bump the PATCH version: 0.1.0 -> 0.1.1)
#   2-|> bash scripts/release.sh --minor  (bump the MINOR version:     0.1.1 -> 0.2.0)
#   3-|> bash scripts/release.sh --major  (bump the MAJOR version:     0.2.0 -> 1.0.0)
#
# What it does:
#   - bumps the version in `manifest.json` & the `collect.py` header,
#   - regenerates `CHANGELOG.md` from conventional commits (via git-cliff),
#   - commits the change & tags it as `v<version>`.
#
##############################

set -euo pipefail

# default to a patch bump; minor & major only when explicitly requested
BUMP=patch
case "${1:-}" in
  --minor) BUMP=minor ;;
  --major) BUMP=major ;;
  "") : ;;
  *) echo "release: unknown flag '$1' (use --minor or --major)" >&2; exit 1 ;;
esac

# fail loudly on missing tools
for tool in jq sed git-cliff; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "release: '$tool' is required but was not found on PATH" >&2
    exit 1
  }
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# never release over a dirty tree (keeps the release commit predictable)
if ! git diff --quiet; then
  echo "release: working tree is dirty - commit or stash changes first" >&2
  exit 1
fi

MANIFEST="manifest.json"
COLLECTOR="collect.py"

# read the current version & compute the next one
CUR="$(jq -r '.version' "$MANIFEST")"
IFS='.' read -r MAJ MIN PAT <<<"$CUR"
case $BUMP in
  major) NEW="$((MAJ + 1)).0.0" ;;
  minor) NEW="$MAJ.$((MIN + 1)).0" ;;
  *)     NEW="$MAJ.$MIN.$((PAT + 1))" ;;
esac
echo "release: $CUR -> $NEW ($BUMP bump)"

# update the versioned files
jq --arg v "$NEW" '.version = $v' "$MANIFEST" > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"
sed -i -E "s/^(# Version): .*/\1: $NEW/" "$COLLECTOR"

# regenerate the changelog for the new tag, keeping any prior entries
if [[ -f CHANGELOG.md ]]; then
  git-cliff --unreleased --tag "v$NEW" --prepend CHANGELOG.md
else
  git-cliff --unreleased --tag "v$NEW" -o CHANGELOG.md
fi

git add "$MANIFEST" "$COLLECTOR" CHANGELOG.md
git commit -m "chore(release): $NEW"
git tag -m "Wakanda4Ever v$NEW" "v$NEW"

echo "release: committed & tagged v$NEW - Wakanda Forever 🫶🏼"