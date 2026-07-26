---
name: new-light-tool
description: Scaffold a brand-new Light Phone III / LightOS tool from nothing — greenfield branch off the light-sdk clone, tool/lighttool.toml identity, ci/create-tool-repo.sh, CLAUDE.md and 00-ASSESSMENT.md templates, Actions secrets, and a local clone ready for Android Studio. Use when starting a new Light Phone tool, scaffolding a new LP3 tool repo, beginning to build a new tool, setting up a tool project, creating the repo for a planned tool (e.g. Sun & Sky from specs/sun-and-sky.md), or when the user says "I want to build X for my Light Phone."
---

# Scaffold a new Light Phone III tool

One tool = one public repo = one folder = one Android Studio project = one Claude Code session. This skill gets a new tool from "an idea (or a spec) exists" to "a clone with green CI that opens in Android Studio," then hands off to feature work.

`light-workspace/ci/create-tool-repo.sh` already does the mechanical middle of this. **Wrap it; never reimplement it.** It creates the public repo, pushes your branch as `main`, installs the four caller workflows and the PR template, generates `SUBMISSION.md`, writes the README template over the SDK's inherited README, sets topics, and applies branch protection last (so its own setup commit can land directly on `main`). Any of that copied into this skill drifts the moment the script changes.

What the script does *not* do, and this skill must: create the branch, set the tool's identity, place `CLAUDE.md` / `00-ASSESSMENT.md`, get the two Actions secrets in place, make the local clone, and verify the result.

## Before you start

Get three things from the author, and don't guess any of them:

- **Tool slug** — lowercase, hyphenated, becomes the repo name `light-<tool>` and the folder name (`sun-and-sky` → `light-sun-and-sky`).
- **Label** — the on-device display name (`Sun & Sky`). Max 50 chars, no control characters or `<`/`>`.
- **One-line description** — becomes the GitHub repo description, so it's public immediately.

If a spec already exists (`light-workspace/specs/<tool>.md`), read it first — it usually settles the label, permissions, and the identity block. Treat its `lighttool.toml` block as a draft, not a source of truth: `specs/sun-and-sky.md`'s block commits `serverPackage = "com.thelightphone.sdk.emulator"`, which the scaffold script refuses (see Step 2).

Everything below runs against `tyleryancey/*`. **`lightphone/*` is strictly read-only** — no pushes, no issues, no PRs, ever.

## Step 1 — Greenfield branch in the light-sdk clone

`~/Documents/lightphone/light-sdk` is a clone of `tyleryancey/light-sdk`, which mirrors upstream `lightphone/light-sdk` and holds only `main`. It's the staging area for new tools, not a tool repo itself.

```bash
cd ~/Documents/lightphone/light-sdk
git fetch origin
git switch -c <tool> origin/main
```

**Never commit to that clone's `main`.** Its whole job is to stay a clean mirror; a local commit there makes every future upstream comparison lie. The branch you just made is local staging only — the script pushes it to the *new* repo's `main` and never pushes anything to `tyleryancey/light-sdk`.

## Step 2 — Set the tool's identity in `tool/lighttool.toml`

This is the one file that must be right before anything else happens. Edit it on your new branch to exactly this shape:

```toml
[tool]
id            = "dev.tyler.<tool>"   # permanent once published
label         = "<Label>"
versionCode   = 1
versionName   = "0.1.0"
permissions   = []
serverPackage = "com.lightos"
# serverPackage = "com.thelightphone.sdk.emulator"
```

The authority on every rule below is `plugin/src/main/kotlin/com/thelightphone/plugin/LightToolMetadata.kt` (`LightToolPolicy`) in the SDK clone — read it rather than trusting this list if something is rejected:

- **`id`** must match `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$` — reverse-DNS, lowercase, **no hyphens**. The repo is hyphenated and the id is not: `light-ringtone-studio` ↔ `dev.tyler.ringtonestudio`. This is permanent once published (it's the Android package, the content-provider authority, and how Light tracks the tool), so it's worth a second look before committing. Uniqueness is only locally checkable against the five existing tools (`dev.tyler.chess`, `dev.tyler.lightledger`, `dev.tyler.ringtonestudio`, `dev.tyler.sudoku`, `dev.tyler.tides`); global uniqueness is arbitrated by Light, who will tell you if the id is taken.
- **`versionName`** must be strict `x.y.z` — no pre-release suffix, no build metadata, no leading zeros. Light's builder rejects anything else, and `reusable-submission-check.yml` fails the PR before Light ever sees it. Start at `0.1.0`; `1.0.0` only if the first release is genuinely shipping-ready.
- **`versionCode`** starts at `1` and only ever increases (CI enforces monotonicity against the last `v*` tag).
- **`permissions`** may only contain entries from `LightToolPolicy.ALLOWED_PERMISSIONS` — currently INTERNET, ACCESS_NETWORK_STATE, WAKE_LOCK, VIBRATE, POST_NOTIFICATIONS, CAMERA, RECORD_AUDIO, READ_MEDIA_AUDIO, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, NFC. Anything else is a build failure, not a request. Request nothing you can't justify in `00-ASSESSMENT.md`; `[]` is the strongest position with Light's reviewers.
- **`serverPackage`** must be committed as `com.lightos`, with the emulator value on a commented line beneath it. **The SDK's own scaffold commits the inverse** (emulator value live, `com.lightos` commented above) — so this is an edit you must make, not a default you inherit. Light's builder compiles the committed value, so an emulator `serverPackage` produces an APK that cannot bind to LightOS on real hardware. Flipping the two lines locally is the normal way to do AVD work; restore with `git checkout -- tool/lighttool.toml` before committing.

Then **commit it**:

```bash
git add tool/lighttool.toml && git commit -m "tool: set <Label> identity"
```

The commit is not optional bookkeeping. The script's preflight runs `git show "$BRANCH:tool/lighttool.toml"` — it reads *committed* content, so an uncommitted edit leaves it reading `main`'s inherited emulator value and it refuses to scaffold. This is the most common first-run failure.

## Step 3 — Run the scaffold script

From inside the light-sdk clone, with the branch still checked out:

```bash
cd ~/Documents/lightphone/light-sdk
~/Documents/lightphone/light-workspace/ci/create-tool-repo.sh <tool> <branch> "<description>"
```

It prints `OK: https://github.com/tyleryancey/light-<tool>` on success.

Two things about it that aren't obvious:

- It `curl`s the caller workflows and templates from `raw.githubusercontent.com/tyleryancey/light-workspace/main`. Local uncommitted edits under `ci/callers/` or `ci/templates/` are invisible to it — whatever is pushed to `light-workspace`'s `main` is what lands in the new repo. Push workspace changes first if they matter to this scaffold.
- It lands its own setup commit ("ci: adopt reusable workflows from light-workspace") from a temp clone, *then* enables branch protection. So don't make your working clone until this finishes — clone earlier and you get a checkout missing the workflows, and you'll be pushing to a `main` that just became protected.

## Step 4 — Local clone for Android Studio

```bash
cd ~/Documents/lightphone
git clone https://github.com/tyleryancey/light-<tool>.git
cd light-<tool>
git remote add upstream https://github.com/lightphone/light-sdk.git
git fetch upstream
```

The folder name must match the repo name — that one-to-one mapping is what keeps sessions, projects, and repos from being confused for each other. The `upstream` remote is what makes future syncs and `git diff upstream/main` work; add it now, while you remember.

Consequence to internalize immediately: **that `upstream` remote is why every `gh` call needs its repo stated explicitly.** With no default set, `gh` can resolve the base repo to `lightphone/light-sdk` and point writes at a repo that must stay read-only — usually surfacing as a baffling permissions error. Pass `-R tyleryancey/light-<tool>` (or the repo as a positional arg to `gh repo view`, or in the path for `gh api`) on every single call.

`main` is protected now, so all further work goes through PRs from feature branches.

## Step 5 — Templates and the README

The script installed `README.md`, `SUBMISSION.md`, and `.github/pull_request_template.md`. Two docs are yours to place, at the repo root (matching ringtone-studio and tides). `main` is protected, so this happens on a branch — it becomes the repo's first PR:

```bash
W=~/Documents/lightphone/light-workspace
cd ~/Documents/lightphone/light-<tool>
git switch -c docs/plan-of-record
cp $W/ci/templates/CLAUDE.md        CLAUDE.md
cp $W/ci/templates/00-ASSESSMENT.md 00-ASSESSMENT.md
```

Nothing substitutes their placeholders — fill `{{LABEL}}` and `{{ID}}` in by hand, along with everything knowable now. If a spec exists, most of `CLAUDE.md` is a port of it; leave a `TODO:` in place rather than inventing content, because a wrong claim about the SDK costs more than an admitted gap.

Two rules for `CLAUDE.md`: keep its `## lighttool.toml` block byte-matching the real file (siblings do, and a drifted copy is worse than none), and keep "verified SDK facts" strictly to things confirmed by reading SDK source or running code — the doc's value is that it can be trusted over guesswork.

`00-ASSESSMENT.md` is per-tool feasibility: what the tool needs from the platform, whether the SDK actually exposes it (cite the source file), the permission allow-list cross-check, the dependency allow-list check, and the ethos argument. Do this *before* writing feature code — Sun & Sky's spec is a good example of why: the assessment found no location access path exists for tool code, which reshaped v1 into a typed-location design.

**The README prose must be the author's, not templated filler.** `docs/README-CHECKLIST.md` in light-workspace explains what makes each section good and why it exists; point them there. This is the first artifact Light's maintainers and the community see — before anyone opens a source file — and Light's stated approval bar is whether a tool "matches the Light ethos both functionally and aesthetically." A README that reads as filled-in boilerplate fails that bar before the code gets a chance. A short, honest paragraph in the author's own voice beats every TODO left in place.

Commit these, but hold the PR until Step 6's secrets are in place:

```bash
git add -A && git commit -m "docs: add plan of record and feasibility assessment"
git push -u origin docs/plan-of-record
```

## Step 6 — Secrets (interactive; you stop and wait here)

CI cannot pass without two Actions secrets, so they must be set **before the first PR opens**. Print these for the human to run in their own terminal, then **stop and wait for them to confirm both are set** — do not proceed to Step 7 on your own:

```bash
gh secret set LIGHT_PACKAGES_TOKEN -R tyleryancey/light-<tool>
gh secret set LIGHT_CI_PAT         -R tyleryancey/light-<tool>
```

The secret **name** is the argument. The value is pasted at the hidden prompt `gh` puts up. Resume only once both names appear:

```bash
gh secret list -R tyleryancey/light-<tool>
```

That lists names and update times, never values — which is exactly why it's the right way to confirm.

**Never accept a token as a command-line argument, never echo one, and never run these on the human's behalf with a value inline.** A token on a command line is captured by shell history, process listings, and this transcript. That has already happened once in this workspace and forced a rotation — the constraint exists because of a real incident, not out of caution. If a token appears anywhere in a command you are about to run, stop and hand the command back instead.

What each one is for, so you can explain it rather than recite it:

| secret | scopes | who uses it |
|---|---|---|
| `LIGHT_PACKAGES_TOKEN` | classic PAT, `read:packages` | `reusable-check.yml` and `reusable-release.yml` — fetching the SDK's GitHub Packages artifacts. Without it Gradle 401s and nothing builds. |
| `LIGHT_CI_PAT` | classic PAT, `repo` + `workflow` | `reusable-sync.yml` only. The sync workflow pushes branches that touch `.github/workflows/`, which `GITHUB_TOKEN` can never do — hence the `workflow` scope and a PAT at all. |

Failure signature worth naming up front: if the first PR's `check / check` dies immediately on a GitHub Packages 401, `LIGHT_PACKAGES_TOKEN` is missing or expired. Set it, then re-run the job — nothing about the code is wrong.

Classic PATs expire. When either token rotates, it has to be re-set on *every* tool repo.

## Step 7 — Verify

```bash
R=tyleryancey/light-<tool>
gh repo view $R --json visibility,defaultBranchRef,repositoryTopics
gh api repos/$R/branches/main/protection --jq '.required_status_checks.contexts'
gh api repos/$R/contents/.github/workflows --jq '[.[].name]'
```

Expect: public, default branch `main`; protection contexts exactly `check / check` and `submission-check / submission-check`; all four workflows present (`check.yml`, `submission-check.yml`, `release.yml`, `sync.yml`). Then open Step 5's branch as the first PR and confirm CI goes green:

```bash
gh pr create -R $R --fill
gh pr checks -R $R
```

A green first PR is the real end of scaffolding. Everything before it is unverified setup.

## Working conventions in the new repo

- **Merge PRs with `--merge`. Never squash, never rebase.** Squashing drops upstream's commits from `main`'s ancestry, and every later upstream sync then re-conflicts against history it can no longer find. This is not a style preference; it's the thing that keeps syncing viable.
- **CI is shared.** The four workflows in each repo are ~10-line callers of reusable workflows in `tyleryancey/light-workspace`, referenced `@main`. Shared CI changes land once, in light-workspace, and apply to every tool repo. Never copy workflow logic into a tool repo — that's how a fleet fragments.
- **Gradle needs GitHub Packages credentials locally** too: `GH_PACKAGES_USER`/`GH_PACKAGES_TOKEN` env vars, or `gpr.user`/`gpr.key` in `local.properties`. The SDK README's own property names for these are wrong.
- Occasional SDK patches outside `tool/` are allowed but flagged by CI as a warning — they should be tracked toward upstreaming (`docs/UPSTREAM-BACKLOG.md`), issue-first, since `lightphone/*` is read-only from here.

## Where to go next

- **`run-light-tool`** — build, install, launch, and drive the tool on the AVD or a physical LP3. Use it as soon as there's a screen to look at; a tool that has never been driven on-device is unverified regardless of what tests pass.
- **`release-tool`** — cut the first release once QA'd (tag `v<versionName>`; the `release` workflow builds and publishes from the tag).
- **`sync-resolve`** — when the weekly upstream sync PR conflicts.
- Feature work itself is driven by `CLAUDE.md`'s milestones. Keep that doc current as the plan of record; when the SDK source contradicts it, the source wins and the doc gets updated.

## Sharp edges

- The script's serverPackage preflight reads the **committed** file. Uncommitted identity edits → it refuses with `serverPackage="com.thelightphone.sdk.emulator"`.
- Tool `id` takes no hyphens, and is permanent once published. The repo name does take them. They will not match, and that's correct.
- Don't clone the new repo until the script has finished; the workflows arrive in its setup commit.
- Don't set secrets by passing values on the command line — Step 6 exists for this reason alone.
- Every `gh` call names its repo explicitly, or it may silently address `lightphone/light-sdk`.
- Spec files can be stale on `serverPackage` and on SDK capabilities. Verify against SDK source, not against the spec.
