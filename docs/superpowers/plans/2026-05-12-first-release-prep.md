# First Release Preparation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 第一次跑 `npm run release` 之前，把 GitHub 端三個容易踩坑的設定提前確認，並提供一個拋棄式 dry-run 步驟驗證整條鏈，最後正式發版第一個 fork 版本號（建議 `v1.1.0-rc.2-tw.1`）。

**Architecture:** 四階段流水線：
- **Phase A** — 端到端 pre-flight check（GitHub 設定、本機狀態、版本號決策）
- **Phase B** — 可選 dry-run（`v0.0.0-smoke.1` 拋棄式版本，驗證 Actions + GHCR）
- **Phase C** — 正式發版（`npm run release v1.1.0-rc.2-tw.1`）
- **Phase D** — 發版後驗證 + 清理 + 寫進文件

**Tech Stack:** GitHub Actions, GHCR, gh CLI, bash scripts（已建立）

---

## 為何需要這份 plan

前一輪 ([2026-05-12-release-automation.md](2026-05-12-release-automation.md)) 已經把自動化機制建好，但**還沒實機發版過**。第一次發版風險集中在 GitHub 端設定，而不是 script 邏輯。本 plan 把這些 trap 預先攔下來。

---

## Phase A：發版前 Pre-flight Check

### Task A1：確認 GitHub Actions Workflow Permissions

**Files:** 不動

- [ ] **Step 1：用 gh CLI 檢查當前 permissions 設定**

```bash
gh api repos/TW199501/tududi/actions/permissions/workflow
```

預期欄位之一：`"default_workflow_permissions": "write"` 與 `"can_approve_pull_request_reviews": true|false`（無關緊要）。

**如果是 `"default_workflow_permissions": "read"`**：必須改成 write，否則 workflow 推不了 GHCR、開不了 Release。

- [ ] **Step 2：（若需要）改設定**

```bash
gh api -X PUT repos/TW199501/tududi/actions/permissions/workflow \
  -f default_workflow_permissions='write' \
  -F can_approve_pull_request_reviews=false
```

或在 GitHub web UI：`Settings → Actions → General → Workflow permissions → Read and write permissions → Save`。

- [ ] **Step 3：再次驗證**

```bash
gh api repos/TW199501/tududi/actions/permissions/workflow | grep default_workflow
```

預期 `"default_workflow_permissions": "write"`。

---

### Task A2：確認 gh CLI 已登入且有正確 scopes

**Files:** 不動

- [ ] **Step 1：檢查 gh 狀態**

```bash
gh auth status
```

預期輸出包含：
```
✓ Logged in to github.com as TW199501
✓ Token scopes: 'repo', 'workflow', 'read:packages', 'write:packages'
```

**若沒有 `write:packages`**：

```bash
gh auth refresh -h github.com -s write:packages,read:packages
```

跟著瀏覽器確認流程走完。

---

### Task A3：確認本機分支狀態

**Files:** 不動

- [ ] **Step 1：確認在 dev 且乾淨**

```bash
git switch dev
git status -s
```

預期 `git status -s` 輸出**空**（沒有 dirty changes）。

- [ ] **Step 2：確認 dev 已 push 到 origin**

```bash
git log origin/dev..dev
```

預期輸出**空**（沒有未 push 的 local commits）。若有，先 `git push origin dev`。

- [ ] **Step 3：確認 release 分支跟 dev 還沒分歧**

```bash
git log --oneline release..dev | head -10
```

預期看到一串 commits（這些就是這次發版要納入的內容）。

```bash
git log --oneline dev..release
```

預期**空**（release 不該領先 dev）。若有，先處理：可能 release 之前手動動過。

---

### Task A4：版本號決策

**Files:** 不動

- [ ] **Step 1：列出候選版本號並選一個**

| 候選 | 語意 | 撞 upstream 風險 |
|------|------|------------------|
| `v1.1.0-rc.2-tw.1` | 接 upstream rc.2、第 1 個 fork 變體（**推薦**） | 零 |
| `v1.1.0-rc.3` | 接續 upstream rc 編號 | 高 |
| `v1.1.0-tw.1` | 視為 rc 完成、開始 fork 自己的 minor track | 零，但偏離 upstream |
| `v0.1.0` | 完全獨立編號系統 | 零，但不貼近上游語意 |

- [ ] **Step 2：在進入 Phase B/C 前明確記下選擇**

可以寫在本 plan 末尾「Versioning Decision」段，避免之後忘記。

---

## Phase B（可選）：Dry-Run with throwaway version

**目的：** 用 `v0.0.0-smoke.1` 之類拋棄式版本驗證 GitHub Actions → GHCR push → Release create 整條鏈，避免在「正式版本號」上踩坑出醜。**信心十足可跳過直接到 Phase C。**

### Task B1：跑 dry-run

**Files:** 不動

- [ ] **Step 1：在 dev 上跑 release 腳本（拋棄式版號）**

```bash
npm run release v0.0.0-smoke.1
```

預期本機輸出：
```
==> Pushing dev to origin...
==> Switching to release and merging dev...
==> Bumping version and creating tag v0.0.0-smoke.1...
==> Pushing release branch and tag...
==> Returning to dev and syncing version bump commit...

✓ Released v0.0.0-smoke.1
  Tag pushed:        v0.0.0-smoke.1
  GitHub Actions:    https://github.com/TW199501/tududi/actions/workflows/docker-release.yml
  Release page:      https://github.com/TW199501/tududi/releases/tag/v0.0.0-smoke.1
  Docker image:      ghcr.io/tw199501/tududi:v0.0.0-smoke.1
```

- [ ] **Step 2：監控 GitHub Actions 進度（~3-5 分鐘）**

```bash
gh run watch
```

或開瀏覽器到上面印出的 Actions URL。

預期：workflow 跑完 status 為 `success`（綠勾）。

**若失敗的處理：** 看 step 哪一步 failed，常見三類：
- `permission denied to ghcr.io` → 回 Task A1 確認 workflow permissions
- `docker build failed` → Dockerfile 在 ubuntu runner 上有問題（複製貼上 log，後續分析）
- `release create failed: HTTP 403` → Token 沒 release 權限（回 Task A1）

### Task B2：清理 dry-run 痕跡

**Files:** 不動

- [ ] **Step 1：刪 GitHub Release**

```bash
gh release delete v0.0.0-smoke.1 --yes
```

- [ ] **Step 2：刪 git tag（local + remote）**

```bash
git tag -d v0.0.0-smoke.1
git push origin :refs/tags/v0.0.0-smoke.1
```

- [ ] **Step 3：刪 GHCR image**

```bash
# 看 package version ID
gh api /user/packages/container/tududi/versions --jq '.[] | select(.metadata.container.tags[] | contains("smoke")) | {id, tags: .metadata.container.tags}'

# 用上面拿到的 id（X 換成實際數字）
gh api -X DELETE /user/packages/container/tududi/versions/<X>
```

- [ ] **Step 4：還原 package.json（dry-run 的 release commit 改了 version）**

兩個分支都動過 package.json，需要還原：

```bash
# release 分支
git switch release
git reset --hard release~1     # 刪掉「release: v0.0.0-smoke.1」commit
git push --force-with-lease origin release

# dev 分支（如果 release.sh 已 merge 回來）
git switch dev
git log --oneline | head -3    # 確認 release: v0.0.0-smoke.1 commit 是否在 dev
# 若在：
git reset --hard <previous-commit-sha>
git push --force-with-lease origin dev
```

**注意：** `--force-with-lease` 是有條件的 force push，比 `--force` 安全，但仍是 destructive。若覺得太冒險，**不還原 package.json 也可以**——之後 Phase C 的真實發版會再次 bump version、覆蓋掉 smoke 留下的版本字串。

### Task B3：GHCR Package 設成 public

**Files:** 不動

第一次推 GHCR 後 package 預設是 private，需要手動改成 public 才能 `docker pull` 不要 login：

- [ ] **Step 1：在瀏覽器確認 / 改設定**

```
https://github.com/users/TW199501/packages/container/tududi/settings
→ Change visibility → Public
```

- [ ] **Step 2：驗證**

```bash
# 開個無痕視窗 / 新 docker context
docker pull ghcr.io/tw199501/tududi:v0.0.0-smoke.1
```

若你已經在 Task B2 刪了 smoke image，就只是驗證後續 Phase C 推上來的 image 會是 public。

---

## Phase C：正式發版

### Task C1：發版

**Files:** 不動

- [ ] **Step 1：確認在 dev 乾淨（重複 A3 step 1 確認）**

```bash
git switch dev
git status -s   # 必須空
```

- [ ] **Step 2：跑！**

```bash
npm run release v1.1.0-rc.2-tw.1
```

（或 Task A4 你選的其他版本號）

- [ ] **Step 3：監控 Actions（~3-5 分鐘）**

```bash
gh run watch
```

預期：綠勾 `success`。

---

### Task C2：發版後三項驗證

**Files:** 不動

- [ ] **Step 1：Docker image 確實在 GHCR**

```bash
docker pull ghcr.io/tw199501/tududi:v1.1.0-rc.2-tw.1
docker inspect ghcr.io/tw199501/tududi:v1.1.0-rc.2-tw.1 | grep -i created
```

預期 `created` timestamp 在剛剛這 5 分鐘內。

- [ ] **Step 2：GitHub Release 存在且有 notes**

```bash
gh release view v1.1.0-rc.2-tw.1
```

預期能看到 Release notes（auto-generated from commits between previous tag and this tag）。

- [ ] **Step 3：image 可以實際跑起來**

```bash
docker run --rm -d --name tududi-release-test \
  -p 3003:3002 \
  -e TUDUDI_USER_EMAIL=test@local.test \
  -e TUDUDI_USER_PASSWORD=test12345 \
  -e TUDUDI_SESSION_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))") \
  -e DISABLE_TELEGRAM=true \
  ghcr.io/tw199501/tududi:v1.1.0-rc.2-tw.1

sleep 10
curl.exe -s -o /dev/null -w "HTTP %{http_code}\n" http://localhost:3003/api/registration-status

docker stop tududi-release-test
```

預期 `HTTP 200`。若 200 = 第一次發版完成端到端驗證 ✓。

---

## Phase D：發版後紀錄 + 文件更新

### Task D1：紀錄第一次發版的 lessons learned

**Files:**
- Modify: `docs/superpowers/plans/2026-05-12-first-release-prep.md` (這份 plan)

- [ ] **Step 1：在本 plan 末尾追加一段 "Post-Release Notes"**

包含：
- 哪個 step 卡住、怎麼解的
- 實際發版花的時間（本機 + Actions）
- 任何 future-self 要避免的雷

範例格式：
```markdown
## Post-Release Notes

**Date:** 2026-MM-DD
**Version released:** vX.Y.Z

### What went smoothly
- ...

### What got stuck
- ...

### Adjustments for next release
- ...
```

### Task D2：把實際發版的版本號回填進 docs/fork-workflow.md

**Files:**
- Modify: `docs/fork-workflow.md`

- [ ] **Step 1：把 fork-workflow.md 範例版本號從 `v0.1.0` 改成你實際用的（如 `v1.1.0-rc.2-tw.1`）**

可在「Release」段：

```diff
-npm run release v0.1.0
+npm run release v1.1.0-rc.2-tw.1
```

並補一段 "Versioning Convention for This Fork"（如果還沒寫）：

```markdown
## Versioning Convention for This Fork

Format: `vUPSTREAM_MAJOR.MINOR.PATCH-rc.N-tw.M`

- The first three segments mirror upstream.
- `-rc.N` is upstream's release candidate stage (only present if upstream is in RC).
- `-tw.M` is this fork's variant number; starts at 1 and bumps on every release of new fork-specific changes.

Examples:
- `v1.1.0-rc.2-tw.1` — first fork release built on upstream rc.2 (adds zh-TW i18n, plans, demos)
- `v1.1.0-rc.2-tw.2` — second fork release, still on upstream rc.2 base
- `v1.1.0-rc.3-tw.1` — after upstream bumped to rc.3 and we synced
- `v1.1.0-tw.1` — after upstream finished RC and released v1.1.0
```

- [ ] **Step 2：commit + push**

```bash
git switch dev
git add docs/fork-workflow.md docs/superpowers/plans/2026-05-12-first-release-prep.md
git commit -m "docs: post-release notes for first fork release vX.Y.Z"
git push origin dev
```

---

## Versioning Decision (填寫處)

> **執行 Phase C 前在這裡寫下你選的版本號，之後對照確認**

```
First release version: v____________________
Reason: ____________________
```

---

## Risk Matrix

| Risk | Likelihood | Severity | Mitigation |
|------|-----------|----------|------------|
| Workflow permissions 沒開 → GHCR push 403 | 中（GitHub 預設值） | 高（整條鏈失敗） | Phase A1 提前確認 |
| GHCR package private → 其他人拉不到 | 高（第一次推預設 private） | 中（個人用無影響） | Phase B3 改 public |
| Dockerfile build fail on ubuntu runner | 低（原作者已測） | 高 | Phase B 用 dry-run 早發現 |
| `--force-with-lease` 在清理時誤刪別人推的 commit | 低（你是唯一 push 者） | 中 | 清理 Phase B2 慎重執行 |
| 版本號撞 upstream 真實發的 rc.X | 低 | 中（image 衝突） | Task A4 選 `-tw.N` suffix |
| Release notes 空白 | 低 | 低 | 第二次發版起 `--generate-notes` 有對照 |
| 漏掉某個 backend env var → image 跑不起來 | 低 | 中 | Task C2 step 3 docker run 試一次 |

---

## Spec Coverage Check

| 需求 | Task |
|------|------|
| 「準備第一次發版」 | Phase A 整段 |
| 「驗證 workflow 確實能跑」 | Phase B（dry-run） |
| 「正式發版」 | Phase C |
| 「踩坑後記錄」 | Phase D1 |
| 「文件更新貼近實際版本號」 | Phase D2 |
