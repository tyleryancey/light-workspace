---
name: sync-resolve
description: Resolve a conflicting upstream sync PR locally and land it, in any of the five Light Phone tool repos (light-sudoku, light-chess, light-ledger, light-ringtone-studio, light-tides). Use when a sync PR says "manual resolution needed", when asked to "resolve the upstream sync" or fix merge conflicts after an SDK update, when the sync workflow opened a conflict PR, when a sync PR shows no checks at all, or when syncs appear blocked/stalled in a tool repo.
---

The weekly `sync` workflow merges `upstream/main` (`lightphone/light-sdk`) into each tool repo's `main` via PR. Conflicts confined to `tool/**` it auto-resolves in the tool's favor. When conflicts land **outside** `tool/`, it gives up: it resets the branch to exactly `upstream/main`, pushes, and opens a PR titled "Upstream sync `<date>`: manual resolution needed". That PR is a notification, not something you can merge — it carries none of your resolution. You resolve locally and land your own merge.

Background and rationale live in `light-workspace/docs/SYNCING.md`; this skill is its executable form. Read it if anything here surprises you.

## When this does NOT apply

If the sync PR merged cleanly, or says "auto-resolved", just review the SDK changes and merge it in the browser. No local work needed. This skill is only for the "manual resolution needed" path.

## Layout

Five standalone public repos — `tyleryancey/light-{sudoku,chess,ledger,ringtone-studio,tides}` — cloned at `~/Documents/lightphone/light-<tool>`. Each has `origin` → its own repo and `upstream` → `lightphone/light-sdk`. The tool itself is always the `tool/` module; `tool/lighttool.toml` holds its identity.

**`upstream` is strictly read-only.** Fetch from it freely. Never push to it, and never open issues or PRs against `lightphone/*`.

## Pass `-R tyleryancey/light-<tool>` to every single `gh` call

This is the most important operational detail here. Every clone has an `upstream` remote and no default base repo set, so `gh` may resolve the **base repo to upstream**. `gh pr create` then tries to open your PR against `lightphone/light-sdk` and fails with a misleading pair of errors:

```
No commits between main and <branch>
Head sha can't be blank
```

That error means **base-repo misresolution** — not indexing lag, not a bad branch, not a push that didn't land. Don't retry it or go looking for the branch on GitHub; add `-R` and it works.

Had such a call *succeeded*, it would have opened a PR on a repo we treat as read-only. So this is a safety matter, not just ergonomics. It failed closed this time; don't rely on that.

## The flow

**1. Confirm a clean tree, then fetch both remotes.**

```bash
cd ~/Documents/lightphone/light-<tool>
git status --short          # must be empty
git fetch origin && git fetch upstream main
```

A dirty tree means uncommitted work that a merge could bury or that you could mistake for a conflict resolution. Stop and deal with it first. Note that a modified `tool/lighttool.toml` is usually a leftover emulator `serverPackage` from AVD work — `git checkout -- tool/lighttool.toml` restores it.

**2. Branch from `origin/main`.**

```bash
git checkout -b sync/resolve-upstream-$(date +%Y%m%d) origin/main
```

**Do not name it `sync/upstream-*`.** The sync workflow's `OPEN_SYNC` guard counts open PRs whose head ref starts with `sync/upstream-`, and skips the run when any exists. A resolution branch under that prefix would block every future sync in the repo for as long as your PR stayed open. `sync/resolve-upstream-` deliberately falls outside the prefix.

**3. Merge and resolve.**

```bash
git merge upstream/main
git diff --name-only --diff-filter=U    # the list you have to work through
```

Resolve by path, per the rules below. **Never commit conflict markers.** If a resolution isn't clear, `git merge --abort` and surface the question — a guessed resolution in SDK code is much more expensive to find later than a paused sync.

**4. Verify identity and `serverPackage` before completing the merge.**

```bash
git diff origin/main -- tool/lighttool.toml     # expect empty
grep serverPackage tool/lighttool.toml          # expect com.lightos
```

`origin/main` *is* the pre-merge state, which is what makes this check work at the end without having recorded anything up front.

**5. Complete the merge, then run the real gate locally.**

```bash
git commit --no-edit
./gradlew check
```

`./gradlew check` is the actual gate, not a formality. A sync can bring SDK API changes that break tool code, and that failure is invisible in the conflict list — nothing conflicts, the code just no longer compiles against the new SDK. Finding it here takes minutes; finding it via CI takes a push, a wait, and a second round trip.

**6. Push and open the PR.**

```bash
git push -u origin HEAD
gh pr create -R tyleryancey/light-<tool> --base main \
  --title "Resolve upstream sync $(date +%Y-%m-%d)" \
  --body "Merges upstream/main with conflicts resolved locally per light-workspace/docs/SYNCING.md. Supersedes the bot's manual-resolution PR."
```

Avoid `--fill` here: it would take the title from the head commit, which is the generated `Merge remote-tracking branch 'upstream/main'` — an unhelpful label on a PR someone will read back later to understand a resolution.

**7. Wait for both checks, then merge with `--merge`.**

```bash
gh pr checks <n> -R tyleryancey/light-<tool> --watch
gh pr merge <n> -R tyleryancey/light-<tool> --merge --delete-branch
```

Both `check / check` and `submission-check / submission-check` must pass.

**`--merge`, never `--squash` or `--rebase`.** A squash flattens the merge into a single new commit, which drops upstream's commits from `main`'s ancestry. The next sync's `git merge-base --is-ancestor upstream/main HEAD` then fails, so it re-merges everything you already resolved and re-conflicts — permanently, every week. This is the least obvious and most damaging mistake available in this whole procedure, and nothing warns you: the PR merges green and the breakage only appears at the next sync.

## Resolution rules by path

### `tool/lighttool.toml` — keep OURS

This is the tool's identity: `id`, `label`, `versionCode`, `versionName`, `permissions`, `serverPackage`. Upstream's version is the blank `tool/` sample — taking it renames the tool to the scaffold.

```bash
git checkout --ours tool/lighttool.toml && git add tool/lighttool.toml
```

Take ours wholesale rather than hand-merging field by field; there is nothing in upstream's sample you want. A `--theirs` slip on this one file is the single edit that renames the tool.

It also fails `submission-check` two separate ways, which is worth knowing so that step isn't a coin flip: the sample's `versionCode = 1` isn't monotonic against your last release tag, and its `serverPackage` is `com.thelightphone.sdk.emulator` rather than `com.lightos`. Its `versionName` (`1.0.0`) is valid semver and passes — so if you ever see only *one* of those two failures, the other resolution slipped through rather than the gate being flaky.

That last gate matters beyond CI. Light's build server compiles the **committed** `serverPackage`, so an emulator value yields an APK that cannot bind to LightOS on real hardware. `com.lightos` is the only shippable committed value; the emulator value belongs in a temporary local edit for AVD work only.

One gate here *can* legitimately newly fail after a sync: `permissions` are validated against the SDK's `ALLOWED_PERMISSIONS`, so if upstream tightens that list, a permission the tool has always requested can start erroring. That's real information about the tool, not a resolution mistake — surface it.

### Sample files we deleted that upstream modified — keep the deletion

Chiefly `tool/src/.../sample/HomeScreen.kt`. Upstream keeps editing scaffold files we removed when we built the real tool, which surfaces as a modify/delete conflict (`DU` in `git status`). Keep the deletion:

```bash
git rm <file>
```

### `gradle/libs.versions.toml` — resolve as a union

Take **upstream's** versions for entries present on both sides (upstream owns SDK dependency versions), and preserve **every** tool-specific addition. Then verify:

```bash
git diff upstream/main -- gradle/libs.versions.toml    # additions only, zero deletions
```

This one command validates both halves of the rule, and it does so *because* you took upstream's values for shared entries — those produce no diff at all, so every remaining `+` line is a tool-specific addition. Any `-` line means you dropped a dependency the tool needs, and that surfaces as a build failure rather than anything legible.

### `sdk/`, `plugin/`, `lint-rules/` — prefer upstream, drop the patch

These are private SDK patches. Prefer upstream's version and drop the patch **unless the patch is load-bearing** (tool code won't compile without it).

`light-workspace/docs/UPSTREAM-BACKLOG.md` records every known patch, whether it's load-bearing, and why. Consult it rather than reasoning from the diff — a patch's importance is generally not visible in the file it touches. Known load-bearing patches, both in `light-ledger`:

- `sdk/client/.../LightDb.kt` — the `destructiveMigration` parameter on `buildDatabase`. Three tool call sites pass it; dropping it breaks compilation.
- `plugin/.../LightSdkPlugin.kt` — `isUnitTestConfig`, which exempts unit-test configurations from the dependency-substitution guard. Without it the tool's Robolectric test dependencies fail the guard.

The reason a patch here is *normally* droppable: Light's build server extracts only `tool/lighttool.toml`, `tool/build.gradle.kts`, `tool/src/main/kotlin/**`, and resources/assets, then compiles against **their** pinned SDK. An `sdk/` patch therefore never reaches a published build at all — it buys local-only behavior while costing a merge conflict on every SDK release, and it makes your local build quietly differ from the one Light signs. Dropping it is usually strictly better. If you drop one that isn't already recorded, note it in `UPSTREAM-BACKLOG.md` so the reasoning survives.

## Cleaning up the bot's PR

The conflict-path branch is pinned at exactly `upstream/main`. Once your resolution merge lands, that commit is typically an ancestor of `main`, so GitHub auto-marks the bot PR **MERGED** and `gh pr close` refuses with "Pull request is already merged" — merged is a terminal state.

That refusal is the expected outcome, not a problem to debug. `SYNCING.md` says closing is what releases the `OPEN_SYNC` guard; both are true, because the guard filters on `state=open` and *any* non-open state — closed or merged — releases it. So the guard is already clear.

Leave a comment explaining the supersession, and delete the stale branch if it lingers:

```bash
gh pr comment <bot-pr> -R tyleryancey/light-<tool> \
  --body "Superseded by #<n>, which merged upstream/main with conflicts resolved locally."
gh api -X DELETE repos/tyleryancey/light-<tool>/git/refs/heads/sync/upstream-<date>
```

## Two things that look like breakage but aren't

**A conflicting sync PR shows no check runs at all.** GitHub can't build a merge ref for a conflicting PR, so `pull_request` workflows never fire. Nothing is wrong with CI, and there is no check to wait for — your resolution PR is where checks actually run.

**An open `sync/upstream-*` PR blocks all future syncs in that repo** via the `OPEN_SYNC` guard. The repo silently stops receiving upstream changes, with no failure anywhere to notice. Resolving promptly is what keeps syncing alive — this is the real cost of leaving one of these sitting.

## Finish by verifying

```bash
git fetch origin && git fetch upstream main
git rev-list --count origin/main..upstream/main     # 0 — nothing upstream left unmerged
gh pr list -R tyleryancey/light-<tool> --state open # empty — no sync PR still blocking
git show origin/main:tool/lighttool.toml | grep -E '^(id|label|versionCode|versionName|serverPackage)'
```

Read that last output and confirm the fields are the tool's own, not the scaffold's. Note that `git diff origin/main -- tool/lighttool.toml` is the right check in step 4 but **useless here** — once you've fetched, `origin/main` contains your merge, so you'd be diffing the merged tree against itself and it passes no matter what you clobbered.

All three together confirm the sync actually landed: the first that you merged everything, the second that the guard is clear for next week, the third that you didn't take upstream's scaffold identity along the way.
