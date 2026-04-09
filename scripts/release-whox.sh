#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [--publish-release]"
  echo "Example: $0 0.1.1 --publish-release"
  exit 1
fi

VERSION="$1"
PUBLISH_RELEASE="${2:-}"
DATE_STR="$(date +%Y.%-m.%-d)"
TAG="v${VERSION}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash changes first."
  exit 1
fi

sed -i "s/^version = \".*\"/version = \"${VERSION}\"/" pyproject.toml
sed -i "s/^__version__ = \".*\"/__version__ = \"${VERSION}\"/" whox_cli/__init__.py
sed -i "s/^__release_date__ = \".*\"/__release_date__ = \"${DATE_STR}\"/" whox_cli/__init__.py

git add pyproject.toml whox_cli/__init__.py
git commit -m "release: ${TAG}"
git tag -a "${TAG}" -m "WHOX ${TAG}"
git push whox main
git push whox "${TAG}"

if [[ "${PUBLISH_RELEASE}" == "--publish-release" ]]; then
  gh release create "${TAG}" \
    --repo overviewlabs/WHOX \
    --title "WHOX ${TAG}" \
    --notes "WHOX ${TAG} release"
fi

echo "Done: ${TAG}"
