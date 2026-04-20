#!/usr/bin/env bash
# Verify the active Coder template on the server matches what's on disk,
# by extracting the published tarball and grepping for revert markers.
#
# Usage: ./scripts/verify-active-template.sh [template-name] [version-name]
# Defaults: template=docker, version=active

set -uo pipefail

TEMPLATE=${1:-docker}
VERSION=${2:-}
OUT=/tmp/coder-template-verify
ARCHIVE="$OUT/template.tar"

mkdir -p "$OUT"
rm -rf "$OUT"/*

if [[ -z "$VERSION" ]]; then
  VERSION=active
fi
echo "== template=$TEMPLATE version=$VERSION =="

set -e
coder templates pull "$TEMPLATE" --version "$VERSION" --tar --yes >"$ARCHIVE"
tar xf "$ARCHIVE" -C "$OUT"
set +e

MAIN="$OUT/main.tf"
if [[ ! -f "$MAIN" ]]; then
  echo "error: main.tf not found in archive" >&2
  ls -la "$OUT"
  exit 1
fi

echo
echo "== tr filter presence (should be empty after revert) =="
grep -n "tr -d '\\\\0'" "$MAIN" || echo "(none — tr filter is absent)"

echo
echo "== agent log block presence =="
grep -nE 'Agent log collection|claude-run|/home/coder/logs' "$MAIN" || echo "(none)"

echo
echo "== first 3 lines of startup_script =="
awk '/startup_script = /,0' "$MAIN" | sed -n '1,5p'
