#!/bin/bash
# release.sh - Dispatch a MacGuard release from main
# Usage: ./scripts/release.sh [patch|minor|major]
# Example: ./scripts/release.sh patch
#
# GitHub Actions bumps the version, builds, signs and publishes the release.

set -e

BUMP_TYPE="${1:-patch}"
REPO="royalskynet/MacGuard-Enhanced"

# Validate bump type
case "$BUMP_TYPE" in
    major|minor|patch) ;;
    *)
        echo "Usage: ./scripts/release.sh [patch|minor|major]"
        echo "  patch: 1.3.2 -> 1.3.3 (default)"
        echo "  minor: 1.3.2 -> 1.4.0"
        echo "  major: 1.3.2 -> 2.0.0"
        exit 1
        ;;
esac

command -v gh >/dev/null || { echo "GitHub CLI (gh) is required."; exit 1; }

echo ""
echo "=== MacGuard Release ==="
echo "Repository: $REPO"
echo "Source: remote main (local changes are not included)"
echo "Version bump: $BUMP_TYPE"
echo ""

# Confirm
read -p "Dispatch release workflow? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

gh workflow run release.yml --repo "$REPO" --ref main -f "bump_type=$BUMP_TYPE"

echo ""
echo "=== Release Workflow Dispatched ==="
echo ""
echo "Monitor: https://github.com/$REPO/actions/workflows/release.yml"
echo "Releases: https://github.com/$REPO/releases"
