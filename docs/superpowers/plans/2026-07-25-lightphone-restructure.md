# Light Phone Repo-Per-Tool Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate five Light Phone III tools from one branch-per-tool fork (`tyleryancey/light-tools`) into standalone public repos with shared reusable CI, and return the fork to its role as the upstream-PR vehicle — per the approved spec at `docs/superpowers/specs/2026-07-25-lightphone-dev-workflow-design.md`.

**Architecture:** All shared CI lives in `tyleryancey/light-workspace` as reusable GitHub Actions workflows; each tool repo carries four ~10-line callers. Tool repos are created by pushing existing branches (history preserved) and configured by one idempotent setup script. Migration is strictly additive until a final, verification-gated fork cleanup.

**Tech Stack:** git, `gh` CLI, GitHub Actions (reusable workflows), Gradle/AGP (Kotlin Android via light-sdk), Android Studio.

## Global Constraints

- Work from `/Users/tyleryancey/Documents/lightphone` unless a step says otherwise.
- `gh` must be authenticated as `tyleryancey` (verify in Task 1). All new repos are **public**, named `light-<tool>`.
- **Nothing is deleted, reset, or force-pushed until its replacement is verified.** Task 8 (fork cleanup) runs only after its listed preconditions pass.
- **`lightphone/*` repos are read-only.** No issues, PRs, comments, or pushes to upstream from this plan (upstream's issue-first rule + AI policy make that human-only).
- Never commit conflict markers. Any merge that cannot be fully resolved is aborted.
- Reusable workflows are referenced as `tyleryancey/light-workspace/.github/workflows/<name>.yml@main`.
- Scratchpad/spec content going into the **public** workspace repo needs the user's OK before push (checkpoint in Task 3).
- The five tools and their fork branches: sudoku, chess, ledger, ringtone-studio, tides. Local folders: `light-tools` (clone, on `sudoku`, hosts worktrees), `light-tools-correspondence-chess` (worktree, `chess`), `light-tools-ledger` (worktree, `ledger`, **28 unpushed commits**), `light-tools-ringtone-studio` (worktree registered as `rt-worktree`, `ringtone-studio`), `light-tools-tides` (separate clone, `tides`), `light-sdk` (vendor clone of upstream), `light-tools-sun-and-moon` (not a repo).

---

### Task 1: Secure at-risk work (push ledger, commit chess tweaks)

**Files:**
- Modify (commit): `light-tools-correspondence-chess/settings.gradle.kts`, `light-tools-correspondence-chess/tool/lighttool.toml`, `light-tools-correspondence-chess/gradle/gradle-daemon-jvm.properties` (untracked → tracked)

**Interfaces:**
- Produces: `origin/ledger` == local `ledger`; `origin/chess` == local `chess` with a clean tree. Task 5/6 push these refs to the new repos.

- [ ] **Step 1: Verify gh auth and freshen remote view**

```bash
gh auth status
git -C light-tools fetch origin --prune
git -C light-tools-tides fetch origin --prune
```
Expected: `Logged in to github.com account tyleryancey`; fetches succeed.

- [ ] **Step 2: Push the 28 unpushed ledger commits**

```bash
git -C light-tools-ledger push origin ledger
git -C light-tools-ledger rev-list --count origin/ledger..ledger
```
Expected: push succeeds; count prints `0`.

- [ ] **Step 3: Commit and push chess device-config tweaks**

```bash
cd light-tools-correspondence-chess
git add settings.gradle.kts tool/lighttool.toml gradle/gradle-daemon-jvm.properties
git commit -m "chore(chess): commit device-config tweaks for LP3 testing

serverPackage=com.lightos, Gradle daemon JVM props, foojay resolver."
git push origin chess
git status -s
cd ..
```
Expected: commit created; push succeeds; `git status -s` prints nothing.

---

### Task 2: Defuse the fork hazards (sync PRs, sync branches, cron)

**Interfaces:**
- Consumes: nothing. Produces: fork has no open PRs, no `sync/*` branches, no scheduled workflow that could fire mid-migration.

- [ ] **Step 1: Disable the fork's scheduled sync workflow** (its weekly cron fires Mondays 09:00 UTC — imminent)

```bash
gh workflow disable sync-upstream.yml -R tyleryancey/light-tools
gh workflow list -R tyleryancey/light-tools
```
Expected: `sync-upstream` shows `disabled_manually`.

- [ ] **Step 2: Close PRs #3 and #4** (their branches contain committed conflict markers)

```bash
gh pr close 3 -R tyleryancey/light-tools -c "Superseded: sync strategy moves to per-tool repos (see light-workspace spec). Branch contains committed conflict markers and is stale vs sudoku."
gh pr close 4 -R tyleryancey/light-tools -c "Superseded: sync strategy moves to per-tool repos (see light-workspace spec). Branch contains committed conflict markers."
gh pr list -R tyleryancey/light-tools --state open
```
Expected: no open PRs remain.

- [ ] **Step 3: Delete the two sync branches**

```bash
git -C light-tools push origin --delete sync/main-into-sudoku sync/main-into-ledger
```
Expected: both deletions confirmed (`- [deleted]`).

---

### Task 3: Rescue unversioned work into light-workspace; publish the repo

**Files:**
- Create: `light-workspace/specs/sun-and-sky.md` (copy of `light-tools-sun-and-moon/CLAUDE-sun-and-sky.md`)
- Create: `light-workspace/notes/2026-07-sync-conflict-recipe.md` (from `Untitled_chess` — it is the sync-conflict recipe, despite the filename)
- Create: `light-workspace/notes/2026-07-sudoku-and-ledger-notes.md` (from `Untitled_ledger`)
- Create: `light-workspace/notes/2026-07-sudoku-kickoff-notes.md` (from `Untitled_sudoku`)
- Create: `light-workspace/notes/2026-07-sudoku-todos.md` (from `Untitled_sudoku2`)

**Interfaces:**
- Produces: public repo `tyleryancey/light-workspace` on GitHub with `main` pushed. Tasks 4–6 depend on it existing.

- [ ] **Step 1: Copy the at-risk files in (originals stay in place until aftercare)**

```bash
cd light-workspace
mkdir -p specs notes
cp ../light-tools-sun-and-moon/CLAUDE-sun-and-sky.md specs/sun-and-sky.md
cp ../Untitled_chess  notes/2026-07-sync-conflict-recipe.md
cp ../Untitled_ledger notes/2026-07-sudoku-and-ledger-notes.md
cp ../Untitled_sudoku notes/2026-07-sudoku-kickoff-notes.md
cp ../Untitled_sudoku2 notes/2026-07-sudoku-todos.md
git add specs notes && git commit -m "docs: rescue unversioned specs and scratchpads into version control"
```
Expected: commit with 5 new files.

- [ ] **Step 2: USER CHECKPOINT — confirm public content.** Show the user the file list (`git show --stat HEAD`) and confirm they're OK with these notes being in a public repo. If any file should stay private, move it to a local `private/` dir added to `.gitignore` and amend the commit before pushing.

- [ ] **Step 3: Create the GitHub repo and push**

```bash
gh repo create tyleryancey/light-workspace --public --description "Light Phone III tools workspace: shared reusable CI, cross-tool docs, specs, and notes" --source . --push
git branch -vv
```
Expected: repo created; `main` tracking `origin/main`, in sync.

---

### Task 4: Author the reusable CI, caller templates, and shared docs

**Files (all in `light-workspace/`):**
- Create: `.github/workflows/reusable-check.yml`, `.github/workflows/reusable-submission-check.yml`, `.github/workflows/reusable-release.yml`, `.github/workflows/reusable-sync.yml`
- Create: `ci/callers/check.yml`, `ci/callers/submission-check.yml`, `ci/callers/release.yml`, `ci/callers/sync.yml`
- Create: `ci/templates/pull_request_template.md`, `ci/templates/SUBMISSION.md`
- Create: `ci/create-tool-repo.sh` (executable)
- Create: `docs/SYNCING.md`

**Interfaces:**
- Produces: reusable workflows callable at `tyleryancey/light-workspace/.github/workflows/reusable-<name>.yml@main`; caller templates fetched raw by the setup script; `ci/create-tool-repo.sh <tool> <source-branch> "<description>"` run from a light-tools clone. Tasks 5–6 consume all of these.
- Design note (refines spec §4.3): a git merge *driver* cannot handle modify/delete conflicts — which are exactly what upstream sample-file edits vs. our deletions produce — so `tool/**` auto-resolution is a scripted classification pass in `reusable-sync.yml` (same outcome, wider coverage), not a `.gitattributes` driver.

- [ ] **Step 1: Write `.github/workflows/reusable-check.yml`**

```yaml
name: reusable-check
on:
  workflow_call: {}
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: gradle/actions/wrapper-validation@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: gradle
      - name: Gradle check
        run: ./gradlew check
        env:
          GITHUB_ACTOR: ${{ github.actor }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
Before committing, compare with the SDK's own `.github/workflows/pr-check.yml` (present in every tool branch, e.g. `light-tools/.github/workflows/pr-check.yml`): if it pins a different Java version or extra setup (e.g. Android SDK setup steps), mirror that setup here. If CI later fails with a 401 fetching GitHub Packages, add repo secrets `GPR_USER`/`GPR_TOKEN` (a classic PAT with `read:packages` — user creates it at github.com/settings/tokens) and pass them as `ORG_GRADLE_PROJECT_gpr.user`/`gpr.key` env vars.

- [ ] **Step 2: Write `.github/workflows/reusable-submission-check.yml`**

```yaml
name: reusable-submission-check
on:
  workflow_call: {}
jobs:
  submission-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: versionName is strict semver
        run: |
          VN=$(sed -n 's/^versionName *= *"\(.*\)".*/\1/p' tool/lighttool.toml)
          echo "versionName=$VN"
          echo "$VN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
            || { echo "::error::versionName '$VN' must be strict x.y.z semver (Light's builder rejects pre-release/build metadata)"; exit 1; }
      - name: versionCode monotonic vs last release tag
        run: |
          VN=$(sed -n 's/^versionName *= *"\(.*\)".*/\1/p' tool/lighttool.toml)
          VC=$(sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p' tool/lighttool.toml)
          LAST=$(git tag -l 'v*' --sort=-v:refname | head -1)
          if [ -z "$LAST" ]; then echo "no v* tags yet; skipping"; exit 0; fi
          PREV_VN=${LAST#v}
          PREV_VC=$(git show "$LAST:tool/lighttool.toml" | sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p')
          echo "version=$VN($VC) last-release=$PREV_VN($PREV_VC)"
          if [ "$VN" != "$PREV_VN" ]; then
            # This PR preps a new release: versionCode must strictly increase.
            [ "$VC" -gt "$PREV_VC" ] \
              || { echo "::error::versionName changed ($PREV_VN -> $VN) but versionCode $VC is not > $PREV_VC (Light's build server rejects non-increasing versionCode)"; exit 1; }
          else
            # No release prepped by this PR: codes should simply not regress.
            [ "$VC" -ge "$PREV_VC" ] \
              || { echo "::error::versionCode $VC regressed below released $PREV_VC"; exit 1; }
          fi
      - name: flag build-affecting changes outside tool/
        run: |
          git fetch origin main --quiet
          BAD=$(git diff --name-only origin/main...HEAD \
            | grep -E '^(sdk/|plugin/|lint-rules/|settings\.gradle|build\.gradle|gradle/libs\.versions\.toml|gradle/wrapper/)' || true)
          if [ -n "$BAD" ]; then
            echo "::warning::Build-affecting changes outside tool/ (intentional SDK patch awaiting upstreaming?):"
            echo "$BAD"
          fi
      - name: permissions restricted to the SDK allow-list
        run: |
          POLICY=$(grep -rl 'ALLOWED_PERMISSIONS' sdk/ | head -1)
          [ -n "$POLICY" ] || { echo "::warning::could not locate ALLOWED_PERMISSIONS in sdk/; skipping"; exit 0; }
          REQUESTED=$(sed -n '/^permissions *=/s/.*\[\(.*\)\].*/\1/p' tool/lighttool.toml | tr -d '" ' | tr ',' '\n' | sed '/^$/d')
          for p in $REQUESTED; do
            grep -q "$p" "$POLICY" \
              || { echo "::error::permission '$p' not found in the SDK allow-list ($POLICY)"; exit 1; }
          done
          echo "permissions OK: ${REQUESTED:-<none>}"
```

- [ ] **Step 3: Write `.github/workflows/reusable-release.yml`**

```yaml
name: reusable-release
on:
  workflow_call: {}
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: tag must match lighttool.toml versionName
        run: |
          VN=$(sed -n 's/^versionName *= *"\(.*\)".*/\1/p' tool/lighttool.toml)
          [ "v$VN" = "$GITHUB_REF_NAME" ] \
            || { echo "::error::tag $GITHUB_REF_NAME != versionName $VN in tool/lighttool.toml"; exit 1; }
      - name: versionCode strictly greater than previous release's
        run: |
          VC=$(sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p' tool/lighttool.toml)
          git fetch --tags --quiet
          PREVTAG=$(git tag -l 'v*' --sort=-v:refname | grep -v "^${GITHUB_REF_NAME}$" | head -1)
          if [ -n "$PREVTAG" ]; then
            PREV_VC=$(git show "$PREVTAG:tool/lighttool.toml" | sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p')
            [ "$VC" -gt "$PREV_VC" ] \
              || { echo "::error::versionCode $VC must be > $PREV_VC (previous release $PREVTAG)"; exit 1; }
          fi
      - name: SUBMISSION.md must reference this version
        run: |
          VN=${GITHUB_REF_NAME#v}
          grep -q "$VN" SUBMISSION.md \
            || { echo "::error::SUBMISSION.md does not mention version $VN — update it before releasing"; exit 1; }
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: gradle
      - name: build sideloadable APK (debug-signed; Light signs official builds)
        run: ./gradlew :tool:assembleDebug
        env:
          GITHUB_ACTOR: ${{ github.actor }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: create GitHub Release with APK
        run: |
          APK=$(ls tool/build/outputs/apk/debug/*.apk | head -1)
          NAME="${GITHUB_REPOSITORY#*/}-${GITHUB_REF_NAME}-debug.apk"
          cp "$APK" "$NAME"
          gh release create "$GITHUB_REF_NAME" "$NAME" --title "$GITHUB_REF_NAME" --generate-notes
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 4: Write `.github/workflows/reusable-sync.yml`**

```yaml
name: reusable-sync
on:
  workflow_call: {}
jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: attempt upstream merge
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          git config user.name  "light-sync bot"
          git config user.email "actions@users.noreply.github.com"
          git remote add upstream https://github.com/lightphone/light-sdk.git
          git fetch upstream main --quiet
          if git merge-base --is-ancestor upstream/main HEAD; then
            echo "Already up to date with upstream/main."; exit 0
          fi
          BRANCH="sync/upstream-$(date +%Y%m%d)"
          git checkout -b "$BRANCH"
          if git merge --no-edit upstream/main; then
            RESULT=clean
          else
            UNMERGED=$(git diff --name-only --diff-filter=U)
            OUTSIDE=$(echo "$UNMERGED" | grep -v '^tool/' || true)
            if [ -z "$OUTSIDE" ]; then
              # All conflicts are inside tool/ — our tool module always wins.
              # DU = deleted by us (we removed the sample; upstream edited it) -> stay deleted.
              # UD/UU/AA = keep our version.
              git status --porcelain | awk '$1=="DU"{print $2}' | xargs -r git rm -f --quiet --
              git status --porcelain | awk '$1=="UD"||$1=="UU"||$1=="AA"{print $2}' \
                | xargs -r -I{} sh -c 'git checkout --ours -- "{}" && git add -- "{}"'
              git commit --no-edit
              RESULT=resolved
            else
              git merge --abort
              git reset --hard upstream/main
              RESULT=conflict
            fi
          fi
          git push origin "$BRANCH"
          if [ "$RESULT" = conflict ]; then
            gh pr create --base main --head "$BRANCH" \
              --title "Upstream sync $(date +%Y-%m-%d): manual resolution needed" \
              --body "$(printf 'Merging upstream/main conflicts outside tool/ in:\n\n%s\n\nResolve locally per light-workspace/docs/SYNCING.md. This branch is pinned at upstream/main — no conflict markers are committed.' "$OUTSIDE")"
          else
            gh pr create --base main --head "$BRANCH" \
              --title "Upstream sync $(date +%Y-%m-%d)" \
              --body "Merge of upstream/main ($RESULT). tool/ conflicts, if any, auto-resolved in this repo's favor. Review the SDK changes and merge when CI is green."
          fi
```

- [ ] **Step 5: Write the four caller templates in `ci/callers/`**

`ci/callers/check.yml`:
```yaml
name: check
on:
  pull_request: {}
jobs:
  check:
    uses: tyleryancey/light-workspace/.github/workflows/reusable-check.yml@main
```

`ci/callers/submission-check.yml`:
```yaml
name: submission-check
on:
  pull_request: {}
jobs:
  submission-check:
    uses: tyleryancey/light-workspace/.github/workflows/reusable-submission-check.yml@main
```

`ci/callers/release.yml`:
```yaml
name: release
on:
  push:
    tags: ['v*']
jobs:
  release:
    uses: tyleryancey/light-workspace/.github/workflows/reusable-release.yml@main
    permissions:
      contents: write
```

`ci/callers/sync.yml`:
```yaml
name: sync
on:
  schedule:
    - cron: '0 14 * * 1'
  workflow_dispatch: {}
jobs:
  sync:
    uses: tyleryancey/light-workspace/.github/workflows/reusable-sync.yml@main
    permissions:
      contents: write
      pull-requests: write
```

- [ ] **Step 6: Write `ci/templates/pull_request_template.md`**

```markdown
## What

-

## QA checklist

- [ ] `./gradlew check` green locally
- [ ] Exercised on the emulator
- [ ] Release-worthy changes: installed and exercised on the physical LP3 via Android Studio
- [ ] `tool/lighttool.toml` `versionName`/`versionCode` bumped if this lands user-facing changes
```

- [ ] **Step 7: Write `ci/templates/SUBMISSION.md`** (`{{...}}` fields are filled by `create-tool-repo.sh`)

```markdown
# Tool Library Submission — {{LABEL}}

- **Name:** {{LABEL}}
- **Tool ID:** {{ID}}
- **Description:** TODO: one paragraph, in Tyler's own words.
- **Repository:** https://github.com/{{REPO}}
- **Commit:** the SHA of the release tag — `git rev-list -n 1 v{{VERSION}}`
- **Version:** {{VERSION}} (versionCode {{VERSIONCODE}})
- **Permissions:** {{PERMISSIONS}}
- **Build command:** `./gradlew :tool:assembleRelease`
- **Testing notes:** QA'd on the LightOS emulator and on a physical Light Phone III via Android Studio.
```

- [ ] **Step 8: Write `ci/create-tool-repo.sh`** (idempotence not required — it is run once per tool; it must be safe to re-run only up to the step that failed)

```bash
#!/usr/bin/env bash
# Usage: ci/create-tool-repo.sh <tool> <source-branch> "<description>"
# Run from within a clone of tyleryancey/light-tools that has <source-branch> as a local branch.
set -euo pipefail
TOOL="$1"; BRANCH="$2"; DESC="$3"
REPO="tyleryancey/light-$TOOL"
RAW="https://raw.githubusercontent.com/tyleryancey/light-workspace/main"

gh repo create "$REPO" --public --description "$DESC"
git push "https://github.com/$REPO.git" "refs/heads/$BRANCH:refs/heads/main"

TMP=$(mktemp -d)
git clone --quiet "https://github.com/$REPO.git" "$TMP/repo"
cd "$TMP/repo"

mkdir -p .github/workflows
for wf in check submission-check release sync; do
  curl -fsSL "$RAW/ci/callers/$wf.yml" -o ".github/workflows/$wf.yml"
done
curl -fsSL "$RAW/ci/templates/pull_request_template.md" -o .github/pull_request_template.md
rm -f .github/workflows/sync-upstream.yml .github/workflows/pr-check.yml

if [ ! -f SUBMISSION.md ]; then
  ID=$(sed -n 's/^id *= *"\(.*\)".*/\1/p' tool/lighttool.toml)
  LABEL=$(sed -n 's/^label *= *"\(.*\)".*/\1/p' tool/lighttool.toml)
  VN=$(sed -n 's/^versionName *= *"\(.*\)".*/\1/p' tool/lighttool.toml)
  VC=$(sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p' tool/lighttool.toml)
  PERMS=$(sed -n '/^permissions *=/s/.*\[\(.*\)\].*/\1/p' tool/lighttool.toml)
  curl -fsSL "$RAW/ci/templates/SUBMISSION.md" \
    | sed -e "s|{{LABEL}}|$LABEL|g" -e "s|{{ID}}|$ID|g" -e "s|{{REPO}}|$REPO|g" \
          -e "s|{{VERSION}}|$VN|g" -e "s|{{VERSIONCODE}}|$VC|g" -e "s|{{PERMISSIONS}}|${PERMS:-none}|g" \
    > SUBMISSION.md
fi

git add -A
git commit -m "ci: adopt reusable workflows from light-workspace"
git push origin main

# Sync workflow opens PRs from Actions:
gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
  -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true

gh repo edit "$REPO" --add-topic lightphone --add-topic lightos --add-topic light-phone-3

# Branch protection last (so the setup commit above could land directly on main):
gh api -X PUT "repos/$REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {"strict": false, "contexts": ["check / check", "submission-check / submission-check"]},
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 0},
  "restrictions": null
}
JSON
echo "OK: https://github.com/$REPO"
```

- [ ] **Step 9: Write `docs/SYNCING.md`** (formalizes the `notes/2026-07-sync-conflict-recipe.md` scratchpad)

```markdown
# Resolving upstream sync conflicts

The weekly sync workflow merges `upstream/main` (lightphone/light-sdk) into each
tool repo's `main` via PR. Conflicts confined to `tool/**` are auto-resolved in
the tool's favor. When the PR says "manual resolution needed", conflicts touch
SDK files this repo has patched. Resolve locally:

1. `git fetch origin && git checkout -b resolve-sync origin/main`
2. `git remote add upstream https://github.com/lightphone/light-sdk.git 2>/dev/null; git fetch upstream main`
3. `git merge upstream/main`, then for each conflict:
   - `tool/lighttool.toml`: keep OUR `id`/`label`/`versionCode`/`permissions`;
     ensure `versionName` stays strict `x.y.z` semver (upstream's builder enforces it).
   - Sample files we deleted that upstream modified (e.g. `tool/.../sample/*`): keep the
     deletion — `git rm <file>`.
   - SDK files we patched: prefer upstream's version if our patch has landed upstream;
     otherwise re-apply our patch on top and note it as a candidate to upstream (issue-first).
4. `./gradlew check`, push, and retarget/replace the sync PR with this branch.

Never commit conflict markers. If in doubt, abort (`git merge --abort`) and ask for review.
```

- [ ] **Step 10: Commit and push everything; verify workflow files parse**

```bash
cd light-workspace
chmod +x ci/create-tool-repo.sh
git add .github ci docs/SYNCING.md
git commit -m "ci: reusable check/submission-check/release/sync workflows, caller templates, setup script, SYNCING doc"
git push origin main
gh api repos/tyleryancey/light-workspace/actions/workflows --jq '.workflows[].name'
```
Expected: push succeeds; the four `reusable-*` workflow names are listed (reusable workflows appear once referenced or on push; absence of YAML syntax errors is confirmed by `gh workflow list` not erroring and by Task 5's live run).

---

### Task 5: Create `light-sudoku` (pilot: full setup + tags + releases + CI smoke test)

**Interfaces:**
- Consumes: `ci/create-tool-repo.sh`, caller templates (Task 4); local branch `sudoku` in `light-tools` (Task 1).
- Produces: verified pattern + tag mapping convention for Task 6. Tag mapping for sudoku: `sudoku-v1.1→v1.1.0`, `sudoku-v1.2→v1.2.0`, `sudoku-v1.3→v1.3.0`, `sudoku-v1.3.1→v1.3.1`, `sudoku-v1.3.2→v1.3.2`.

- [ ] **Step 1: Run the setup script**

```bash
cd light-tools && git fetch origin --prune
bash ../light-workspace/ci/create-tool-repo.sh sudoku sudoku "Sudoku tool for the Light Phone III (built on lightphone/light-sdk)"
```
Expected: ends with `OK: https://github.com/tyleryancey/light-sudoku`.

- [ ] **Step 2: Recreate the five release tags under the plain vX.Y.Z convention and push them**

```bash
cd light-tools
git tag v1.1.0 sudoku-v1.1^{} ; git tag v1.2.0 sudoku-v1.2^{} ; git tag v1.3.0 sudoku-v1.3^{}
git tag v1.3.1 sudoku-v1.3.1^{} ; git tag v1.3.2 sudoku-v1.3.2^{}
git push https://github.com/tyleryancey/light-sudoku.git v1.1.0 v1.2.0 v1.3.0 v1.3.1 v1.3.2
```
Expected: five new tags pushed.

- [ ] **Step 3: Recreate the five GitHub Releases with their APK assets**

```bash
mkdir -p /tmp/sudoku-releases && cd /tmp/sudoku-releases
for pair in sudoku-v1.1:v1.1.0 sudoku-v1.2:v1.2.0 sudoku-v1.3:v1.3.0 sudoku-v1.3.1:v1.3.1 sudoku-v1.3.2:v1.3.2; do
  OLD=${pair%%:*}; NEW=${pair##*:}
  mkdir -p "$OLD" && gh release download "$OLD" -R tyleryancey/light-tools -D "$OLD" 2>/dev/null || true
  gh release view "$OLD" -R tyleryancey/light-tools --json body --jq .body > "$OLD/notes.md"
  gh release create "$NEW" -R tyleryancey/light-sudoku --title "$NEW" --notes-file "$OLD/notes.md" "$OLD"/*.apk 2>/dev/null \
    || gh release create "$NEW" -R tyleryancey/light-sudoku --title "$NEW" --notes-file "$OLD/notes.md"
done
gh release list -R tyleryancey/light-sudoku
```
Expected: five releases listed, `v1.3.2` marked Latest. Spot-check one: `gh release view v1.3.2 -R tyleryancey/light-sudoku` shows the APK asset if the fork release had one.

- [ ] **Step 4: CI smoke test — open a trivial PR, confirm both checks run and pass, fix protection contexts if names differ**

```bash
cd /tmp && git clone https://github.com/tyleryancey/light-sudoku.git && cd light-sudoku
git checkout -b test/ci-smoke
printf '\n' >> tool/README.md 2>/dev/null || printf '\n' >> README.md
git add -A && git commit -m "test: CI smoke" && git push origin test/ci-smoke
gh pr create --title "test: CI smoke" --body "Verifying check + submission-check wiring. Will be closed unmerged."
sleep 90 && gh pr checks
```
Expected: `check / check` and `submission-check / submission-check` both pass. If the reported context names differ, update the protection contexts to the observed names via `gh api -X PATCH repos/tyleryancey/light-sudoku/branches/main/protection/required_status_checks --input -` with the corrected `contexts` array. If `./gradlew check` fails on package auth (401), apply the PAT contingency from Task 4 Step 1 and re-run.

- [ ] **Step 5: Close the smoke PR and delete its branch; verify sync workflow end-to-end**

```bash
gh pr close test/ci-smoke --delete-branch -R tyleryancey/light-sudoku 2>/dev/null || { gh pr close 1 -R tyleryancey/light-sudoku; git push origin --delete test/ci-smoke; }
gh workflow run sync.yml -R tyleryancey/light-sudoku
sleep 120 && gh run list -R tyleryancey/light-sudoku --workflow=sync.yml --limit 1
gh pr list -R tyleryancey/light-sudoku
```
Expected: sync run completes; since fork main lags upstream, a `sync/upstream-<date>` PR appears (clean or resolved — sudoku has SDK patches, so a "manual resolution needed" PR pinned at upstream/main is also a valid outcome; either way, **no conflict markers in the PR diff**). Leave the PR open for the user to review/merge later — merging upstream changes is real work, not migration.

---

### Task 6: Create the remaining four tool repos

**Interfaces:**
- Consumes: verified script + pattern from Task 5; local branches `chess`, `ledger`, `ringtone-studio` in `light-tools`; branch `tides` fetched from origin.
- Produces: `light-chess`, `light-ledger`, `light-ringtone-studio`, `light-tides` live. Tag mapping: `tides-v0.1.0→v0.1.0`; the other three have no tags.

- [ ] **Step 1: Fetch tides into the light-tools clone and run the script four times**

```bash
cd light-tools
git fetch origin tides:tides chess:chess ledger:ledger ringtone-studio:ringtone-studio 2>/dev/null || git fetch origin tides:tides
bash ../light-workspace/ci/create-tool-repo.sh chess chess "Chess (with rules engine and computer opponent) for the Light Phone III"
bash ../light-workspace/ci/create-tool-repo.sh ledger ledger "Personal-finance ledger tool for the Light Phone III (SimpleFIN bank sync)"
bash ../light-workspace/ci/create-tool-repo.sh ringtone-studio ringtone-studio "Ringtone composer for the Light Phone III"
bash ../light-workspace/ci/create-tool-repo.sh tides tides "Tide tables and station search for the Light Phone III"
```
Expected: four `OK:` lines. (The fetch refspecs fail harmlessly for branches that already exist locally; only `tides` is genuinely missing.)

- [ ] **Step 2: Recreate the tides tag**

```bash
git tag v0.1.0 tides-v0.1.0^{}
git push https://github.com/tyleryancey/light-tides.git v0.1.0
```
Expected: tag pushed.

- [ ] **Step 3: Verify each repo's main matches its source branch**

```bash
for t in chess:chess ledger:ledger ringtone-studio:ringtone-studio tides:tides sudoku:sudoku; do
  TOOL=${t%%:*}; BR=${t##*:}
  echo "light-$TOOL: $(gh api repos/tyleryancey/light-$TOOL/branches/main --jq .commit.sha | cut -c1-7) vs local $(git rev-parse --short $BR)"
done
```
Expected: each pair differs only because of the one `ci:` setup commit on the new main — verify with `gh api repos/tyleryancey/light-<tool>/commits/main --jq .parents[0].sha` matching the local branch head for one or two repos.

---

### Task 7: Re-point local folders to the new repos

**Interfaces:**
- Consumes: the five new repos (Tasks 5–6). Produces: local clones `light-sudoku`, `light-chess`, `light-ledger`, `light-ringtone-studio`, `light-tides` with gitignored state carried over; worktrees removed. Old `light-tools` and `light-tools-tides` folders remain (deleted only in aftercare).

- [ ] **Step 1: Clone the five new repos**

```bash
cd /Users/tyleryancey/Documents/lightphone
for t in sudoku chess ledger ringtone-studio tides; do git clone "https://github.com/tyleryancey/light-$t.git"; done
```
Expected: five new folders.

- [ ] **Step 2: Carry over gitignored precious state** (`.superpowers/`, `.remember/`, `.claude/`, `local.properties`, emulator keys)

```bash
carry() { SRC="$1"; DST="$2"; for f in .superpowers .remember .claude local.properties sdk/emulator/keys; do
  [ -e "$SRC/$f" ] && rsync -a "$SRC/$f" "$DST/$(dirname "$f")/" ; done; }
carry light-tools light-sudoku
carry light-tools-correspondence-chess light-chess
carry light-tools-ledger light-ledger
carry light-tools-ringtone-studio light-ringtone-studio
carry light-tools-tides light-tides
ls -a light-ledger | grep -E 'superpowers|remember'
```
Expected: state dirs present in the new clones (ledger shown as the spot check; not every source has every item).

- [ ] **Step 3: Remove the three worktrees (their branches are fully pushed — verified in Tasks 1/6)**

```bash
git -C light-tools worktree remove light-tools-correspondence-chess
git -C light-tools worktree remove light-tools-ledger
git -C light-tools worktree remove ../light-tools-ringtone-studio 2>/dev/null || git -C light-tools worktree remove rt-worktree 2>/dev/null || git -C light-tools worktree list
git -C light-tools worktree list
```
Expected: only the main `light-tools` checkout remains listed. (The ringtone worktree is registered under the name `rt-worktree` — if the path form fails, `git worktree list` shows the exact path to pass.) Worktree removal deletes those folders — their precious state was copied in Step 2 first.

- [ ] **Step 4: Sanity-build one migrated clone**

```bash
cd light-sudoku && ./gradlew :tool:assembleDebug && cd ..
```
Expected: BUILD SUCCESSFUL (first run downloads dependencies; needs the `read:packages` token in `local.properties` carried over in Step 2).

---

### Task 8: Fork cleanup and rename (PRECONDITIONS GATED)

**Preconditions (verify all before any step):** Task 6 Step 3 passed for all five repos; Task 5 releases verified; Task 7 worktrees removed cleanly; user has confirmed go-ahead for the destructive phase.

**Interfaces:**
- Produces: `tyleryancey/light-sdk` (renamed fork) with `main` == `upstream/main`, no tool branches, no releases; local `light-sdk` vendor clone re-pointed at it.

- [ ] **Step 1: Delete the fork's releases and old tags**

```bash
for r in sudoku-v1.1 sudoku-v1.2 sudoku-v1.3 sudoku-v1.3.1 sudoku-v1.3.2; do
  gh release delete "$r" -R tyleryancey/light-tools --yes --cleanup-tag
done
git -C light-tools push origin --delete tides-v0.1.0
```
Expected: five releases+tags gone; tides tag deleted.

- [ ] **Step 2: Delete tool branches and the 12 inherited upstream branches**

```bash
git -C light-tools push origin --delete sudoku chess ledger ringtone-studio tides
git -C light-tools push origin --delete example-tool-qa fix/default-client-filter-level feat/tool-builder \
  fix/tighten-plugin fix-readme-typo fix/pr-builder guy/loading-icon guy/return-home \
  fix/pr-build-test ui-library-authenticator guy/wip-mollysocket weather
```
Expected: all deletions confirmed. (`main` cannot be deleted and isn't listed.)

- [ ] **Step 3: Reset fork `main` to upstream and rename the repo**

```bash
git -C light-tools fetch upstream main
git -C light-tools push origin +refs/remotes/upstream/main:refs/heads/main
gh repo rename light-sdk -R tyleryancey/light-tools --yes
gh repo edit tyleryancey/light-sdk --description "Fork of lightphone/light-sdk — used only for upstream contributions (issue-first)"
gh api repos/tyleryancey/light-sdk/branches --jq '.[].name'
```
Expected: force-push accepted; rename succeeds; branch list shows only `main`. (The force-push drops the 8 sync-workflow commits — their only content, `sync-upstream.yml`, is superseded by the reusable sync; the workflow was already disabled in Task 2.)

- [ ] **Step 4: Re-point the local vendor clone at the renamed fork**

```bash
cd light-sdk
git remote rename origin upstream
git remote add origin https://github.com/tyleryancey/light-sdk.git
git fetch origin && git branch -u origin/main main
git remote -v && git status -sb
cd ..
```
Expected: `origin`=tyleryancey/light-sdk, `upstream`=lightphone/light-sdk, `main...origin/main` in sync; untracked `CLAUDE.md` still present (untracked files are unaffected).

---

### Task 9: Final verification sweep + aftercare checklist

**Files:**
- Create: `light-workspace/docs/AFTERCARE.md`

- [ ] **Step 1: Cross-repo verification**

```bash
for t in sudoku chess ledger ringtone-studio tides; do
  echo "== light-$t =="
  gh repo view tyleryancey/light-$t --json isPrivate,defaultBranchRef --jq '[.isPrivate, .defaultBranchRef.name] | @tsv'
  gh api repos/tyleryancey/light-$t/branches/main/protection --jq '.required_status_checks.contexts' 2>/dev/null || echo "NO PROTECTION"
done
gh release list -R tyleryancey/light-sudoku | head -3
git -C light-ledger log --oneline -3
```
Expected: all five public with default branch `main` and protection contexts set; sudoku releases present; ledger history intact in its new clone.

- [ ] **Step 2: Write `docs/AFTERCARE.md`** — user-decision items, not automated:

```markdown
# Aftercare checklist (each item is a user decision)

- [ ] Delete old local folders `light-tools/` and `light-tools-tides/` (everything is pushed; ~1.4 GB back)
- [ ] Delete `light-tools-sun-and-moon/` (spec rescued to specs/sun-and-sky.md) and the four `Untitled_*` files (rescued to notes/)
- [ ] Delete `~/Documents/lightphone.zip` (755 MB) and `~/Documents/light-tools-tides.zip` (79 MB)
- [ ] Review then archive/delete `~/Documents/light-phone-3-lightos-dev/` (1.5 GB; contains an untracked ledger plan doc — check before deleting) and the `tyleryancey/light-sdk-sudoku-port` GitHub repo
- [ ] `./gradlew clean` in idle projects (~2.3 GB regenerable output)
- [ ] Review/merge the open sync PRs the smoke test created in each tool repo
- [ ] Write and file the safe-drawing-insets issue upstream (human-authored, issue-first; patch lives in light-sudoku's sdk/ delta)
- [ ] Post chess, ledger, ringtone-studio, tides in Discussions → Tools; PR all tools to garado/awesome-light
- [ ] Create `run-<tool>` Claude deploy skills in the other four repos, modeled on light-ringtone-studio's
- [ ] First release for chess (SUBMISSION.md exists; tag v1.0.0 when QA'd), ringtone-studio and ledger when ready
```

- [ ] **Step 3: Commit and push**

```bash
cd light-workspace && git add docs/AFTERCARE.md && git commit -m "docs: post-migration aftercare checklist" && git push origin main
```
Expected: pushed.

---

## Self-review notes (spec coverage)

- Spec §4.1 repos → Tasks 3, 5, 6, 8. §4.2 branches/CI/QA/releases/SUBMISSION → Tasks 4–6 (PR template carries the QA checklist; `run-<tool>` skills deliberately deferred to AFTERCARE — they're per-tool dev work, not migration). §4.3 sync → Task 4 Step 4 + Task 5 Step 5 (merge-driver limitation refined to a scripted resolution pass, noted in Task 4 interfaces). §4.4 upstream flow → enforced by Global Constraints (upstream read-only; insets issue is an AFTERCARE human item). §4.5 local layout → Task 7 (+ Task 8 Step 4). §5 migration steps 1–7 → Tasks 1–9 in order. §6 risks → ledger push first (Task 1), PRs closed early (Task 2), release assets downloaded before fork deletion (Task 5 Step 3 before Task 8), rename-redirect assumption not relied on (vendor clone re-pointed explicitly).
