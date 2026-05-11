#!/usr/bin/env bash
# Interactive helper for sending cherry-picked commits as a PR to upstream.
#
# Usage:
#   bash scripts/pr-to-upstream.sh <feature-name>
#   npm run upstream:pr zh-TW-i18n
#
# Flow:
#   1. Fetch upstream
#   2. Show commits on dev not in upstream/main
#   3. Prompt for SHA(s) to cherry-pick
#   4. Build a fresh branch upstream-pr/<feature-name> from upstream/main
#   5. Cherry-pick the chosen commits
#   6. Push to origin
#   7. Open a draft PR on the upstream repo

set -euo pipefail

if ! command -v gh >/dev/null; then
  echo "Error: gh CLI required. Install: https://cli.github.com/" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <feature-name>  e.g. $0 zh-TW-i18n" >&2
  exit 1
fi

FEATURE=$1
BRANCH="upstream-pr/${FEATURE}"

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "Error: no 'upstream' remote configured." >&2
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "Error: working tree has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "Error: branch ${BRANCH} already exists locally." >&2
  echo "       Delete it (git branch -D ${BRANCH}) or pick a different feature name." >&2
  exit 1
fi

echo "==> Fetching upstream..."
git fetch upstream

echo
echo "=== Commits on dev not in upstream/main ==="
git log --oneline upstream/main..dev || true
echo
echo "Copy the SHA(s) you want to cherry-pick (in chronological order, oldest first),"
echo "separated by spaces. Leave empty to abort."
read -rp "SHA(s) to cherry-pick: " SHAS

if [[ -z "${SHAS// }" ]]; then
  echo "Nothing to do." >&2
  exit 0
fi

echo "==> Building ${BRANCH} from upstream/main..."
git switch -c "$BRANCH" upstream/main

echo "==> Cherry-picking: $SHAS"
# shellcheck disable=SC2086
if ! git cherry-pick $SHAS; then
  echo
  echo "Cherry-pick hit a conflict. Resolve manually, then:" >&2
  echo "  git cherry-pick --continue" >&2
  echo "  git push -u origin ${BRANCH}" >&2
  echo "  gh pr create --repo <upstream> --base main --head <you>:${BRANCH} --draft" >&2
  exit 1
fi

echo "==> Pushing to origin..."
git push -u origin "$BRANCH"

UPSTREAM_REPO=$(git remote get-url upstream | sed -E 's|.*github.com[:/]([^/]+/[^/.]+?)(\.git)?$|\1|')
MY_LOGIN=$(gh repo view --json owner -q .owner.login)

echo "==> Opening draft PR on ${UPSTREAM_REPO}..."
gh pr create \
  --repo "$UPSTREAM_REPO" \
  --base main \
  --head "${MY_LOGIN}:${BRANCH}" \
  --title "[${FEATURE}] (suggested)" \
  --body "Cherry-picked from my fork (\`${MY_LOGIN}/tududi\` branch \`${BRANCH}\`).
Happy to revise per project conventions. Opened as draft — feel free to request changes." \
  --draft

cat <<EOF

✓ Draft PR opened against ${UPSTREAM_REPO}

  Local branch:  ${BRANCH}
  Convert to ready-for-review when you want maintainer attention.
  Delete local branch when done:  git switch dev && git branch -D ${BRANCH}
EOF
