# Fork Workflow

This fork (`TW199501/tududi`) follows a three-branch strategy and ships releases
to GHCR via GitHub Actions. Designed so the everyday flow is "**git commit, then
one command**".

## Branches

| Branch | Role | Rule |
|--------|------|------|
| `main` | Mirror of upstream (`chrisvel/tududi`) | **Never commit directly.** Only fast-forwarded from `upstream/main`. |
| `dev` | Active development | Your daily work, feature branches merge here. |
| `release` | Stable, tagged for production | Receives merges from `dev`; each tag triggers a Docker build. |

## Remotes

```
origin    → https://github.com/TW199501/tududi.git   (your fork)
upstream  → https://github.com/chrisvel/tududi.git   (original author)
```

If `upstream` is missing:

```bash
git remote add upstream https://github.com/chrisvel/tududi.git
```

---

## Daily work

```bash
git switch dev
# ... hack ...
git add .
git commit -m "feat: ..."
git push origin dev
```

For larger pieces, use feature branches off `dev`:

```bash
git switch -c feature/my-thing dev
# ... hack ...
git switch dev
git merge --no-ff feature/my-thing
git branch -d feature/my-thing
git push origin dev
```

---

## Sync with upstream (original author)

When chrisvel pushes new commits to their `main`:

```bash
npm run upstream:sync
```

Behind the scenes:
- `git fetch upstream`
- `git switch main && git merge --ff-only upstream/main`
- `git push origin main`

If `main` has diverged (someone accidentally committed to it), the script
refuses to fast-forward and tells you. Fix the divergence manually before
re-running.

To pull those upstream changes into `dev`:

```bash
git switch dev
git merge main
# resolve conflicts if any, then push
git push origin dev
```

---

## Release (the headline feature)

A single command:

```bash
npm run release v1.1.0-rc.2-tw.1
```

This wraps `scripts/release.sh`, which:

1. Verifies you're on `dev` with a clean working tree
2. Pushes `dev` to origin
3. Switches to `release`, fast-forward merges `dev`
4. Runs `scripts/create-version.sh v1.1.0-rc.2-tw.1`
   - Bumps `package.json` version
   - Creates `release: v1.1.0-rc.2-tw.1` commit
   - Creates annotated tag
5. Pushes `release` + the tag to origin
6. Returns to `dev` and merges the version bump commit in
7. Prints URLs for Actions and Releases pages

The tag push triggers `.github/workflows/docker-release.yml`, which:

- Builds a Docker image
- Pushes to `ghcr.io/tw199501/tududi:v1.1.0-rc.2-tw.1` and `:latest`
- Opens a GitHub Release with auto-generated notes

Build takes 3–5 minutes. Watch with:

```bash
gh run list --workflow=docker-release.yml --limit=1
gh run watch    # interactive
```

After it finishes:

```bash
docker pull ghcr.io/tw199501/tududi:v1.1.0-rc.2-tw.1
```

### Version numbering

SemVer with a leading `v`:

```
v0.1.0       stable release
v0.1.0-rc.1  release candidate
v0.1.1       patch
v0.2.0       new feature
v1.0.0       breaking change / first stable
```

### Manual workflow_dispatch

If you forgot to tag locally or want to re-build an existing tag, you can
trigger the workflow from the GitHub UI:

```
Actions → Docker Release → Run workflow → enter tag → Run
```

---

## Send PR to upstream

When you have something worth sharing back with chrisvel:

```bash
npm run upstream:pr zh-TW-i18n
```

This wraps `scripts/pr-to-upstream.sh`, which:

1. Fetches upstream
2. Lists commits on `dev` not in `upstream/main`
3. Prompts you to copy the SHA(s) to cherry-pick
4. Builds `upstream-pr/zh-TW-i18n` from `upstream/main`
5. Cherry-picks the chosen commits
6. Pushes to origin
7. Opens a draft PR on `chrisvel/tududi`

The PR is **draft** by default — review it on GitHub, polish the description,
and click "Ready for review" when satisfied.

### Why cherry-pick instead of merging dev whole?

`dev` accumulates everything (zh-TW translations, your private demo HTML,
investigation notes, ...). The upstream author only wants the *general-purpose*
commits. Cherry-picking lets you slice out just `feat(i18n): zh-TW` without
dragging along your private docs.

### When cherry-pick conflicts

The script will abort and tell you to:

```bash
# resolve conflicts in the listed files
git cherry-pick --continue
git push -u origin upstream-pr/zh-TW-i18n
gh pr create --repo chrisvel/tududi --base main \
  --head TW199501:upstream-pr/zh-TW-i18n --draft
```

---

## Hotfix scenario

Production (`release`) needs an urgent patch:

```bash
git switch release
git switch -c hotfix/critical-fix
# ... fix ...
git commit -am "fix: critical bug in ..."
git switch release
git merge --no-ff hotfix/critical-fix
git branch -d hotfix/critical-fix

npm run release v0.1.1

# don't forget to backport into dev
git switch dev
git merge release
git push origin dev
```

---

## Recipe quick reference

| Goal | Command |
|------|---------|
| Daily commit | `git add . && git commit -m "..." && git push origin dev` |
| Pull upstream changes | `npm run upstream:sync` |
| Ship a release | `npm run release v1.1.0-rc.2-tw.1` |
| Send PR to upstream | `npm run upstream:pr <feature>` |
| Watch build progress | `gh run watch` |
| List recent releases | `gh release list` |
| Pull a built image | `docker pull ghcr.io/tw199501/tududi:v1.1.0-rc.2-tw.1` |
