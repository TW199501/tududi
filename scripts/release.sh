#!/usr/bin/env bash
# One-liner release wrapper.
#
# Usage:
#   bash scripts/release.sh v0.1.0
#   npm run release v0.1.0
#
# Flow:
#   1. Ensure on 'dev' branch with clean working tree
#   2. Push dev to origin (so release is built from the published HEAD)
#   3. Switch to release, fast-forward merge dev
#   4. Run scripts/create-version.sh (bumps package.json + creates tag)
#   5. Push release + tag to origin
#   6. Switch back to dev, fast-forward in the version bump commit
#   7. Print URLs for GitHub Actions and Releases page

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>  e.g. $0 v0.1.0" >&2
  exit 1
fi

VERSION=$1

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Error: version must follow SemVer with leading 'v', e.g. v0.1.0 or v0.1.0-rc.1" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "dev" ]]; then
  echo "Error: must be on 'dev' branch to release. Currently on $CURRENT_BRANCH." >&2
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "Error: dev has uncommitted changes. Commit or stash first." >&2
  git status --short >&2
  exit 1
fi

# Detect a running SQLite connection. -shm/-wal sidecars only exist while
# a SQLite connection is open. Release requires switching git branches that
# disagree about whether the DB is tracked, and an open handle prevents the
# swap on Windows ("Invalid argument" on unlink). Bail early with a clear
# message instead of failing mid-pipeline.
if [[ -e backend/database.sqlite-shm || -e backend/database.sqlite-wal ]]; then
  cat >&2 <<MSG
Error: backend/database.sqlite has an open connection (found -shm/-wal sidecars).
       Release switches between branches that disagree on whether the DB is
       tracked; an open SQLite handle prevents the swap on Windows.

Fix:
  1. Stop any running backend dev server (npm run backend:dev / nodemon / docker)
  2. Remove the sidecar files:
        rm backend/database.sqlite-shm backend/database.sqlite-wal
  3. (Optional) Remove the dev DB itself if not needed for now:
        rm backend/database.sqlite
     Recreate later with: npm run db:init && npm run user:create -- ...
  4. Re-run: npm run release $VERSION
MSG
  exit 1
fi

# Also guard against a stale backend/database.sqlite living in working tree
# even with no -shm/-wal: release branch has it tracked, dev branch has it
# untracked. Switching branches with a modified+tracked vs untracked diff
# fails. Demand the user removes the file before continuing.
if git ls-files --error-unmatch backend/database.sqlite >/dev/null 2>&1 ||
   { [[ -e backend/database.sqlite ]] && [[ "$(git rev-parse --abbrev-ref HEAD)" == "dev" ]] && \
     git ls-tree -r release --name-only | grep -q '^backend/database.sqlite$'; }; then
  cat >&2 <<MSG
Error: backend/database.sqlite exists in working tree but release branch
       still tracks it. Switching branches will fail.

Fix:
  rm backend/database.sqlite
  (Or stash via: git stash push --include-untracked)
  Re-run: npm run release $VERSION
MSG
  exit 1
fi

if git show-ref --tags --verify --quiet "refs/tags/$VERSION"; then
  echo "Error: Tag $VERSION already exists." >&2
  exit 1
fi

echo "==> Pushing dev to origin..."
git push origin dev

echo "==> Switching to release and merging dev..."
git switch release
git pull --ff-only origin release
git merge --ff-only dev

echo "==> Bumping version and creating tag $VERSION..."
bash scripts/create-version.sh "$VERSION"

echo "==> Pushing release branch and tag..."
git push origin release
git push origin "refs/tags/$VERSION"

echo "==> Returning to dev and syncing version bump commit..."
git switch dev
git merge release  # release is ahead by the version bump commit

REPO=$(git remote get-url origin | sed -E 's|.*github.com[:/]([^/]+/[^/.]+?)(\.git)?$|\1|')

cat <<EOF

✓ Released $VERSION

  Tag pushed:        $VERSION
  GitHub Actions:    https://github.com/${REPO}/actions/workflows/docker-release.yml
  Release page:      https://github.com/${REPO}/releases/tag/$VERSION  (available after build finishes)
  Docker image:      ghcr.io/$(echo "${REPO%%/*}" | tr '[:upper:]' '[:lower:]')/tududi:$VERSION

Build takes ~3-5 minutes. Check progress with: gh run list --workflow=docker-release.yml --limit=1
EOF
