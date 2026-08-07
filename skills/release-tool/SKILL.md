---
name: release-tool
description: Promote a Light Phone tool from QA to a tagged GitHub release with a sideloadable APK — light-sudoku, light-chess, light-ledger, light-ringtone-studio, light-tides. Use when asked to cut a release, ship version X, tag and publish, bump the version, prepare a release APK, promote a tool to prod, or when a release workflow failed after the tag was already pushed and the tag needs cleaning up. Runs a local preflight that mirrors CI's tag / versionName / versionCode / SUBMISSION.md gates before the tag goes to GitHub.
---

# Release a Light Phone tool

## Why this skill exists

Each tool repo's `release` workflow triggers on `push: tags: ['v*']`. Everything it
asserts, it asserts *after* the tag exists on GitHub. If the tag doesn't match
`versionName`, or `versionCode` didn't increase, or `SUBMISSION.md` still says the old
version, the run fails with the tag already pushed — and cleanup means deleting it in
two places (remote and local) before you can retry. There is no `--force` shortcut that
makes that pleasant.

Every one of those assertions is checkable locally in about a second. That's the whole
point of this skill: turn an awkward-to-undo state into "caught before push."

## Layout

Five repos, `tyleryancey/light-{sudoku,chess,ledger,ringtone-studio,tides}`, cloned at
`~/Documents/lightphone/light-<tool>`. Tool identity — `id`, `label`, `versionCode`,
`versionName`, `permissions`, `serverPackage` — lives in `tool/lighttool.toml`.

**Pass `-R tyleryancey/light-<tool>` to every `gh` call.** Each clone has an `upstream`
remote pointing at `lightphone/light-sdk`. With no default set, `gh` can resolve the base
repo to *upstream*, which produces misleading errors (`No commits between…`) and, worse,
aims a write at a repo that must stay read-only. Pin it every time.

## 1. Confirm device QA happened — ask, don't assume

CI cannot see a phone. Dev happens on the emulator; **QA means the build was installed on
the physical Light Phone III via Android Studio and actually exercised.** Ask the human
directly whether that happened for the commit being released, and don't proceed on
silence. If it hasn't, use the `run-light-tool` skill (or the repo's own
`run-<tool>` skill, e.g. `.claude/skills/run-ringtone-studio/`) to build, install, and
drive it on the device first.

## 2. Preflight

```bash
~/Documents/lightphone/light-workspace/skills/release-tool/scripts/preflight.sh ~/Documents/lightphone/light-<tool>
```

(Also reachable as `~/.claude/skills/release-tool/scripts/preflight.sh` once the skill is
symlinked there. The argument defaults to the current directory.)

It prints each check with its actual and expected values and exits non-zero on the first
hard failure. What it checks, and which CI job would otherwise catch it:

| check | mirrors | notes |
|---|---|---|
| on `main`, clean tree, HEAD == `origin/main` | the flow itself | a stray emulator `serverPackage` edit surfaces as a dirty tree |
| `versionName` is strict `x.y.z` | `submission-check` | no pre-release, no build metadata — Light's builder rejects them; this rule already forced a real rename from `1.3` to `1.3.0` |
| `serverPackage` == `com.lightos` | `submission-check` | committed value is what Light compiles; an emulator value yields an APK that can't bind to LightOS on hardware |
| tag `v<versionName>` doesn't exist yet | (implicitly) `release` | a leftover tag from a failed attempt is exactly the recovery case below |
| `versionCode` > previous release tag's | `release` **and** `submission-check` | `versionName` and `versionCode` move as a pair |
| `SUBMISSION.md` mentions the version | `release` | |

Two things the script deliberately does *not* do, so you don't over-trust a green run:

- **Permissions.** `submission-check` checks each entry in `permissions = [...]` against
  the SDK's `ALLOWED_PERMISSIONS` list, and warns-and-skips if it can't locate that file.
  Reproducing its file-guessing locally risks a false failure that blocks a legitimate
  release, so let the PR gate own it. (It also warns, non-blocking, about
  build-affecting changes outside `tool/`.)
- **The build.** Only `check / check` on the PR and the release job itself compile
  anything. Preflight is metadata.

Three fidelity notes worth knowing at the wrong moment:

- **The SDK validates `versionName` more strictly than CI does, and it does so at build
  time.** Both preflight and `submission-check` use `^[0-9]+\.[0-9]+\.[0-9]+$`, which
  accepts leading zeros (`01.2.3` passes). The SDK's own
  `LightToolPolicy.VERSION_NAME_PATTERN` is `^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$`
  and rejects them, and it runs at Gradle-configure time — so a leading-zero version goes
  green through preflight *and* the PR, then fails inside the release job's build, after
  the tag is already pushed. That is exactly the state this skill exists to avoid, so
  don't write leading zeros. Preflight deliberately keeps CI's looser regex rather than
  the stricter one, because matching CI byte-for-byte is what makes it a faithful mirror.

- The "previous release" both CI and preflight compare against is the
  **highest-sorting** `v*` tag (`--sort=-v:refname`), not the most recent one. If a
  release ever went out of order, they agree with each other and both compare against
  the wrong tag.
- The `SUBMISSION.md` version check is a plain `grep`, so dots match any character. It's
  *permissive*, not strict — it can pass while the file still says the old version
  somewhere. Eyeball the file.

## 3. If a version bump is needed, land it through a PR

`main` is protected: changes arrive by PR with `check / check` and
`submission-check / submission-check` green (0 approvals required). A version bump is an
ordinary change and gets the ordinary treatment — do not push to `main`.

Edit both halves together, because they are one fact in two fields:

- `tool/lighttool.toml` — `versionName` **and** `versionCode`. `versionCode` is a plain
  increment; `versionName` is the semver users see.
- `SUBMISSION.md` — the `**Version:**` line (`1.3.2 (versionCode 6)`) and the
  `**Commit:**` line's `git rev-list -n 1 v<version>` hint.

```bash
cd ~/Documents/lightphone/light-<tool>
git checkout -b release/v1.3.2
# edit tool/lighttool.toml and SUBMISSION.md
git commit -am "Bump to 1.3.2 (versionCode 6)"
git push -u origin release/v1.3.2
gh pr create -R tyleryancey/light-<tool> --fill
gh pr checks -R tyleryancey/light-<tool> --watch
gh pr merge -R tyleryancey/light-<tool> --merge --delete-branch
```

**`--merge`, never `--squash` or `--rebase`.** Squashing drops upstream's commits from
`main`'s ancestry, and every future sync from `lightphone/light-sdk` then re-conflicts on
work that was already merged.

Then `git checkout main && git pull` and re-run the preflight — it should now be green on
a `main` that matches `origin/main`.

## 4. Tag and push

Only after preflight is green and device QA is confirmed:

```bash
cd ~/Documents/lightphone/light-<tool>
git tag v1.3.2            # LIGHTWEIGHT only — never `git tag -a` (see below)
git push origin v1.3.2
```

**The tag must be lightweight, not annotated.** Proven on light-wiki v0.1.0
(2026-08-07): for a tag-triggered run, `actions/checkout@v4` force-rewrites
the local tag ref to the *peeled commit* (`+<GITHUB_SHA>:refs/tags/vX.Y.Z`).
The release workflow's versionCode step then runs `git fetch --tags --quiet`,
which for an annotated tag tries to replace that commit ref with the tag
*object*, refuses to clobber, and exits 1 — **silently**, because `--quiet`
suppresses the rejection line. The step fails with no output before any
assertion runs, after the tag is already pushed. A lightweight tag is the
same sha as what checkout wrote, so the fetch is a no-op. Release notes
belong in the GitHub release (the workflow passes `--generate-notes`), not
in the tag object.

## 5. Watch, then verify

```bash
gh run list -R tyleryancey/light-<tool> --workflow release --branch v1.3.2   # eyeball it
gh run watch -R tyleryancey/light-<tool> "$(gh run list -R tyleryancey/light-<tool> \
  --workflow release --branch v1.3.2 --limit 1 --json databaseId --jq '.[0].databaseId')"
gh release view v1.3.2 -R tyleryancey/light-<tool>
```

`--branch v1.3.2` matters: for a tag-triggered run the head branch *is* the tag, and
without it `--limit 1` hands you the newest `release` run for any ref — a different tag,
or a re-run.

The release is done when it exists *with the APK attached* — named
`light-<tool>-v1.3.2-debug.apk`. A release with no asset means the build step failed
after `gh release create` ran, or the workflow died mid-way; treat it as a failure and
recover.

## Recovery — the tag is pushed and the workflow failed

This is the state the preflight exists to prevent, and the one you'll actually need
instructions for.

```bash
gh run view -R tyleryancey/light-<tool> --log-failed   # read the actual assertion first
git push origin :refs/tags/v1.3.2                      # delete remotely
git tag -d v1.3.2                                      # delete locally — both, or the next push no-ops
gh release delete v1.3.2 -R tyleryancey/light-<tool> --yes   # only if a release object exists
```

Fix the cause (a metadata fix goes through a PR, per step 3), then re-tag and push again.

**Do not just re-run the failed job.** The workflow has no idempotency guard, so if
`gh release create` already succeeded, a re-run fails on the existing release even though
the underlying problem is fixed. Delete and re-tag instead.

## What the artifact actually is

The workflow runs `./gradlew :tool:assembleDebug` and attaches that APK. It is
**debug-signed, for sideloading only.** Light signs official builds themselves, from your
public commit, compiling only the `tool/` module against their pinned SDK. Never present
a GitHub release APK as a vetted or official build — and expect Light-gated APIs (e.g.
`SetRingtone`) to return `NoPermission` on a real, non-vetted device.

## After the release

Briefly, because the sharing path is still manual:

- The GitHub release URL is the distribution link today.
- Post it in Light's Discussions → Tools.
- PR the tool to the community directory `garado/awesome-light`.
- `SUBMISSION.md` exists to be copy-paste-ready for Light's official Tool Library
  submission when that opens. Keeping it accurate at release time is the whole reason CI
  gates on it.
