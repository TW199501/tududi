#!/usr/bin/env bash
# Sync main with upstream/main and push to origin.
#
# Usage:
#   bash scripts/sync-upstream.sh
#   npm run upstream:sync
#
# Refuses to proceed if main has diverged from upstream/main (you have local
# commits on main that aren't in upstream). The point of this script is to
# keep main as a pure mirror — fix the divergence manually before re-running.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "Error: no 'upstream' remote configured." >&2
  echo "  Add it with: git remote add upstream https://github.com/chrisvel/tududi.git" >&2
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "Error: working tree has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "==> Fetching upstream..."
git fetch upstream

echo "==> Switching to main..."
git switch main

echo "==> Fast-forwarding main to upstream/main..."
if ! git merge --ff-only upstream/main; then
  echo "Error: main has diverged from upstream/main." >&2
  echo "       This means someone (or some action) committed directly to main." >&2
  echo "       Fix it manually — possibly: git reset --hard upstream/main  (destroys local main commits)" >&2
  git switch "$CURRENT_BRANCH"
  exit 1
fi

echo "==> Pushing main to origin..."
git push origin main

echo "==> Returning to $CURRENT_BRANCH..."
git switch "$CURRENT_BRANCH"

cat <<EOF

✓ main synced with upstream/main and pushed to origin

  To pull these changes into dev:    git merge main
  To pull them into release:         git switch release && git merge main
EOF
