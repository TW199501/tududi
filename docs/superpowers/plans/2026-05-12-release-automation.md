# Fork Workflow & Release Automation Plan

> 對應的執行者：未來開啟新會話的 Claude 或本人。**REQUIRED SUB-SKILL**：實作時使用 `superpowers:executing-plans`。Steps 用 `- [ ]` checkbox 追蹤。

**Goal：** 讓「dev 分支上累積 commits → 發版 → docker image → GitHub Release → 通知原作者」這條鏈，在本地只需要**一句話**就能跑完。所有重活（build、push、發 Release）交給 GitHub Actions。

**Architecture：** 本機腳本只做四件低風險動作（切分支、merge、tag、push）。Tag push 觸發 GitHub Actions workflow，runner 上做 docker buildx、推 GHCR、開 GitHub Release。送 PR 給原作者是獨立流程，半自動（cherry-pick 由人決定）。

**Tech Stack：**
- GitHub Actions（`workflow_dispatch` + `push.tags`）
- Docker Buildx（先 amd64，未來補 arm64）
- GitHub Container Registry（`ghcr.io/TW199501/tududi`）—免費、用 `GITHUB_TOKEN` 即可推
- gh CLI（PR 流程）
- bash scripts in `scripts/`

---

## 三條工作鏈

### 鏈 A：日常開發（不變）

```
dev 上開 feature branch → 改 code → commit → merge 回 dev → push origin dev
```

這個 plan **不動**這條鏈。

### 鏈 B：發版（自動化重點）

```
本機: npm run release v0.1.0
   ↓
本機 scripts/release.sh:
   1. 確認當前在 dev 且乾淨
   2. switch release
   3. fast-forward merge dev → release
   4. 跑現有 scripts/create-version.sh v0.1.0
      （更新 package.json version + commit + annotated tag）
   5. push release + tag 到 origin
   ↓
GitHub Actions (tag push 觸發):
   1. checkout
   2. docker buildx build
   3. push to ghcr.io/TW199501/tududi:v0.1.0 + :latest
   4. gh release create v0.1.0 --generate-notes
      （從 commit log 自動產 Release Notes）
   5. attach docker pull 指令到 Release body
```

### 鏈 C：送 PR 給原作者（半自動）

```
本機: npm run upstream:pr v0.1.0
   ↓
本機 scripts/pr-to-upstream.sh:
   1. fetch upstream/main
   2. 互動式：列出 dev 領先 main 的 commits，讓你勾選哪些送 PR
   3. 建臨時 branch from upstream/main，cherry-pick 選中 commits
   4. push 到 origin（forked repo）
   5. gh pr create --repo chrisvel/tududi --base main 開 draft PR
```

---

## File Structure

| 路徑 | 動作 | 角色 |
|------|------|------|
| `.github/workflows/docker-release.yml` | **Create** | Tag 觸發的 docker build + GitHub Release |
| `.github/workflows/upstream-sync-check.yml` | **Create**（可選） | 每日 cron 檢查 upstream 有新 commit 時開 issue 提醒 |
| `scripts/release.sh` | **Create** | 一句話發版 wrapper |
| `scripts/pr-to-upstream.sh` | **Create** | 半自動送 PR |
| `scripts/sync-upstream.sh` | **Create** | 手動同步 main |
| `docs/fork-workflow.md` | **Create** | 給未來自己（或新成員）的操作指南 |
| `package.json` | **Modify** | 加 `release`、`upstream:pr`、`upstream:sync` 三個 npm scripts |
| `scripts/create-version.sh` | 不動 | 既有腳本，被 release.sh 呼叫 |

---

## 設計決策（已預決）

| 決策 | 選擇 | 為什麼 |
|------|------|--------|
| Registry | **GHCR**（`ghcr.io/TW199501/tududi`）| 免費、用 `GITHUB_TOKEN` 不用設第三方 secret、跟 Actions 整合最緊 |
| 多架構 | amd64 only（v1）| 90% 使用者 dev/server 是 x86_64；arm64 留 v2 加 |
| 版本號規範 | SemVer `vMAJOR.MINOR.PATCH` | 業界標準；前綴 `v` 跟既有 `v1.1.0-rc.2` 一致 |
| Release Notes 來源 | GitHub `--generate-notes` 自動 | 從 PR/commit 自動產，免手寫 |
| 發版觸發 | git tag push（`v*` glob）| 標準做法、可審計、可回溯 |
| Docker tag 策略 | `:vX.Y.Z` + `:latest` 同時推 | 鎖版 + 永遠最新版各取所需 |
| 簽名 image (cosign) | **不做**（v1）| 個人 fork 用，過度設計 |
| Sync upstream main | 手動 | 你決定何時 pull，避免衝突當下沒人解 |

---

## 開放問題（需要你回答後才能定）

1. **要不要也推到 Docker Hub？** 還是 GHCR 一個就夠？
2. **dev push 要不要自動發 Release Candidate（如 `v0.1.0-rc.1`）？** 或只有 release 分支 tag 才發版？
3. **release.sh 跑完是不是直接 `gh workflow view --web` 自動打開瀏覽器看進度？** 還是只印 URL？

---

## Task 1：建立 docker-release workflow

**Files:**
- Create: `.github/workflows/docker-release.yml`

- [ ] **Step 1：寫 workflow YAML**

完整內容如下（複製貼上、不需改動）：

```yaml
name: Docker Release

on:
  push:
    tags: ['v*.*.*']
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag to build (e.g. v0.1.0)'
        required: true
        type: string

permissions:
  contents: write   # 開 GitHub Release
  packages: write   # 推 GHCR

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    steps:
      - name: Resolve ref
        id: ref
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            echo "tag=${{ inputs.tag }}" >> "$GITHUB_OUTPUT"
          else
            echo "tag=${GITHUB_REF#refs/tags/}" >> "$GITHUB_OUTPUT"
          fi

      - uses: actions/checkout@v4
        with:
          ref: ${{ steps.ref.outputs.tag }}
          fetch-depth: 0

      - uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/tududi:${{ steps.ref.outputs.tag }}
            ghcr.io/${{ github.repository_owner }}/tududi:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "${{ steps.ref.outputs.tag }}" \
            --title "${{ steps.ref.outputs.tag }}" \
            --generate-notes \
            --notes "
## Docker Image

\`\`\`bash
docker pull ghcr.io/${{ github.repository_owner }}/tududi:${{ steps.ref.outputs.tag }}
\`\`\`

Built from commit \`${{ github.sha }}\`."
```

- [ ] **Step 2：commit + push**

```bash
git switch dev
git add .github/workflows/docker-release.yml
git commit -m "ci: add docker release workflow triggered by version tags"
git push origin dev
```

- [ ] **Step 3：驗證 workflow 在 GitHub 可見**

打開 `https://github.com/TW199501/tududi/actions`，應該看到「Docker Release」workflow，狀態為 idle（還沒被觸發）。

---

## Task 2：建立本機 release wrapper

**Files:**
- Create: `scripts/release.sh`
- Modify: `package.json`（加 npm script）

- [ ] **Step 1：寫 scripts/release.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>  e.g. $0 v0.1.0" >&2
  exit 1
fi

VERSION=$1
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# 前置檢查
if [[ "$(git rev-parse --abbrev-ref HEAD)" != "dev" ]]; then
  echo "Error: must be on 'dev' branch to release. Currently on $(git rev-parse --abbrev-ref HEAD)." >&2
  exit 1
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "Error: dev has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

# 推 dev 到 origin（如果落後）
git push origin dev

# 切 release 並 fast-forward merge dev
git switch release
git pull --ff-only origin release
git merge --ff-only dev

# bump version + tag（用既有 script）
bash scripts/create-version.sh "$VERSION"

# push release + tags
git push origin release
git push origin "refs/tags/$VERSION"

# 切回 dev（同步 version bump commit）
git switch dev
git merge --ff-only release || git merge release  # release 領先 dev 因為有 version bump commit

# 回報
GITHUB_REPO=$(git remote get-url origin | sed -E 's|.*github.com[:/]([^/]+/[^/.]+)(\.git)?|\1|')
echo
echo "✓ Released $VERSION"
echo "  - Tag pushed: $VERSION"
echo "  - GitHub Actions: https://github.com/${GITHUB_REPO}/actions"
echo "  - Release page (after build): https://github.com/${GITHUB_REPO}/releases/tag/$VERSION"
```

- [ ] **Step 2：標可執行 + 加 npm script**

```bash
chmod +x scripts/release.sh
```

`package.json` `scripts` 加一條：
```json
"release": "bash scripts/release.sh"
```

- [ ] **Step 3：commit**

```bash
git add scripts/release.sh package.json
git commit -m "chore: add release wrapper script for one-liner versioning"
git push origin dev
```

---

## Task 3：建立 sync-upstream 腳本

**Files:**
- Create: `scripts/sync-upstream.sh`
- Modify: `package.json`

- [ ] **Step 1：寫腳本**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# 取得當前分支以便最後切回
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 拉 upstream
git fetch upstream

# 切 main 強制 fast-forward
git switch main
if ! git merge --ff-only upstream/main; then
  echo "Error: main diverged from upstream/main. Resolve manually." >&2
  git switch "$CURRENT_BRANCH"
  exit 1
fi

# push 到 origin
git push origin main

# 切回原本分支
git switch "$CURRENT_BRANCH"

echo "✓ main synced with upstream/main and pushed to origin"
echo "  Tip: 若 dev 也想同步，跑: git merge main"
```

- [ ] **Step 2：npm script**

`package.json`：
```json
"upstream:sync": "bash scripts/sync-upstream.sh"
```

- [ ] **Step 3：commit**

```bash
chmod +x scripts/sync-upstream.sh
git add scripts/sync-upstream.sh package.json
git commit -m "chore: add upstream sync wrapper script"
```

---

## Task 4：建立 pr-to-upstream 半自動腳本

**Files:**
- Create: `scripts/pr-to-upstream.sh`
- Modify: `package.json`

- [ ] **Step 1：寫腳本**

```bash
#!/usr/bin/env bash
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

# 同步 upstream
git fetch upstream

# 列 dev 領先 upstream/main 的 commits 供使用者參考
echo
echo "=== Commits on dev not in upstream/main ==="
git log --oneline upstream/main..dev
echo
echo "Copy the SHA(s) you want to cherry-pick, separated by spaces."
read -rp "SHA(s) to cherry-pick: " SHAS

if [[ -z "$SHAS" ]]; then
  echo "Nothing to do." >&2
  exit 0
fi

# 建臨時 branch from upstream/main
git switch -c "$BRANCH" upstream/main

# cherry-pick
# shellcheck disable=SC2086
git cherry-pick $SHAS

# push 到 origin
git push -u origin "$BRANCH"

# 開 PR (draft)
UPSTREAM_REPO=$(git remote get-url upstream | sed -E 's|.*github.com[:/]([^/]+/[^/.]+)(\.git)?|\1|')
gh pr create \
  --repo "$UPSTREAM_REPO" \
  --base main \
  --head "$(gh repo view --json owner -q .owner.login):${BRANCH}" \
  --title "[$FEATURE] (suggested)" \
  --body "Cherry-picked from my fork. Happy to revise per your conventions." \
  --draft

echo
echo "✓ Draft PR opened against $UPSTREAM_REPO"
echo "  Review and convert to ready-for-review when satisfied."
```

- [ ] **Step 2：npm script**

`package.json`：
```json
"upstream:pr": "bash scripts/pr-to-upstream.sh"
```

- [ ] **Step 3：commit**

```bash
chmod +x scripts/pr-to-upstream.sh
git add scripts/pr-to-upstream.sh package.json
git commit -m "chore: add helper script for sending cherry-picked PR upstream"
```

---

## Task 5：寫 docs/fork-workflow.md

**Files:**
- Create: `docs/fork-workflow.md`

- [ ] **Step 1：寫文件**

完整內容（直接複製貼上）：

```markdown
# Fork Workflow

Three-branch strategy for this fork:

| Branch | Role | Source |
|--------|------|--------|
| `main` | Mirror of upstream (chrisvel/tududi) | Never commit directly |
| `dev`  | Active development | Your daily work |
| `release` | Stable, tagged for production | `dev` merges into here |

## Daily commands

```bash
# Start work
git switch dev
# ... hack ...
git add .
git commit -m "..."
git push origin dev
```

## Sync with upstream

```bash
npm run upstream:sync
# main gets fast-forwarded to upstream/main, pushed to your origin
```

If you want dev to absorb upstream changes:

```bash
git switch dev
git merge main
# resolve conflicts, push
```

## Release

```bash
npm run release v0.1.0
# wraps:
#  - switch release, ff-merge dev
#  - bump package.json version + tag
#  - push release + tag
#  - GitHub Actions builds docker, pushes to GHCR, opens GitHub Release
```

Docker image becomes available at:
```
ghcr.io/TW199501/tududi:v0.1.0
ghcr.io/TW199501/tududi:latest
```

## Send PR to upstream

```bash
npm run upstream:pr zh-TW-i18n
# - shows commits ahead of upstream/main
# - prompts which SHAs to cherry-pick
# - opens draft PR on chrisvel/tududi
```

## Hotfix scenario

If production (release) needs urgent patch:

```bash
git switch release
git switch -c hotfix/something
# ... fix ...
git commit -m "..."
git switch release
git merge --no-ff hotfix/something
npm run release v0.1.1
# also merge back to dev
git switch dev && git merge release
```
```

- [ ] **Step 2：commit**

```bash
git add docs/fork-workflow.md
git commit -m "docs: add fork workflow guide"
git push origin dev
```

---

## Task 6：第一次發版實機演練

**Files:** 不動

- [ ] **Step 1：確認 dev 已包含 Task 1–5 所有 commits 並 push**

```bash
git status
git log --oneline origin/dev..dev  # 應該為空
```

- [ ] **Step 2：跑「一句話發版」**

```bash
npm run release v0.1.0
```

預期輸出最後一行：
```
✓ Released v0.1.0
  - Tag pushed: v0.1.0
  - GitHub Actions: https://github.com/TW199501/tududi/actions
  - Release page (after build): https://github.com/TW199501/tududi/releases/tag/v0.1.0
```

- [ ] **Step 3：等 3–5 分鐘讓 Actions 跑完，驗證 3 件事**

```bash
# 1. Workflow 成功
gh run list --workflow=docker-release.yml --limit=1
# expected: completed success

# 2. Docker image 存在
docker pull ghcr.io/TW199501/tududi:v0.1.0
docker inspect ghcr.io/TW199501/tududi:v0.1.0 | grep -i created

# 3. GitHub Release 已開
gh release view v0.1.0
```

---

## 自我檢查

- ✅ 每個 Task 含具體 file path + 可貼上的程式碼
- ✅ Bash scripts 含 set -euo pipefail、錯誤前置檢查
- ✅ workflow 用 GITHUB_TOKEN，無需設第三方 secret
- ✅ 三條鏈 A/B/C 互不干擾（PR 給上游不影響發版）
- ✅ 含真實發版演練（Task 6）驗證整條鏈

## 對應使用者三個原始需求

| 需求 | 對應 Task |
|------|-----------|
| 「一句話勾發版」 | Task 1 + Task 2（npm run release v0.x.y） |
| 「dev 中要發布 Releases 版本」| Task 1（GitHub Release auto-create from tag）|
| 「推送到作者那邊」 | Task 4（npm run upstream:pr）|
