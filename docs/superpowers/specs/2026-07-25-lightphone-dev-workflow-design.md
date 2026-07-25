# Light Phone Tool Development — Environment, Workflow & Organizational Structure

**Date:** 2026-07-25
**Status:** Approved by Tyler (interactive review, section by section)
**Scope:** GitHub account structure, per-tool repo model, SDK sync strategy, upstream contribution flow, local machine layout, and the migration from the current state.

## 1. Goal

Restructure Tyler's Light Phone III tool development so that:

- Multiple tools can be developed and managed simultaneously with no cross-tool friction.
- Every tool is continuously in the shape Light's submission pipeline consumes (public git commit, SDK-shaped repo, tool at `tool/`).
- All three distribution paths are served: (a) own GitHub releases (sideload APKs), (b) the official Light tool-library vetting process when it opens (~late August per maintainer), (c) upstream SDK contributions via PR.
- dev → qa → prod is explicit: dev on emulator via feature branches, QA on the physical LP3 via Android Studio, prod as CI-built, version-tagged GitHub releases.

**Success criteria:** each tool has its own public repo whose `main` builds green and is submission-ready at any commit; upstream SDK updates arrive as reviewable PRs with zero committed conflict markers; no work exists only on one machine or only in gitignored files; the fork serves exclusively as the upstream-PR vehicle.

## 2. Decisions (from interactive Q&A)

| Question | Decision |
|---|---|
| Distribution goals | All three: own GitHub releases + official vetting + upstream PRs |
| Environment meaning | dev = emulator on feature branches; QA = physical LP3 via Android Studio; prod = tagged GitHub release; CI checks gate promotion |
| Migration appetite | Full restructure OK — no work lost, history preserved where it matters |
| Repo visibility | Public from day one |
| Structure | Repo-per-tool (standalone repos) + fork reserved for upstream PRs |
| Naming | `light-<tool>`: light-sudoku, light-tides, light-ledger, light-chess, light-ringtone-studio, light-workspace; fork renamed to light-sdk |

## 3. Research findings that drive the design

### Upstream (`lightphone/light-sdk`)

- **Tools do not live in the SDK repo.** Maintainer (issue #109): community tools will have "a dedicated process… and they won't live in this repo." PRs adding tools to `examples/` sit ignored (PR #122); "Tool library submission" issues get closed-with-redirect (#109) or no answer (#86).
- **The coming official pipeline** (README "Sharing Your Tool" + in-repo `builder/`): all community tools must be open source; Light builds and signs **from a public git commit**, extracting only `tool/`-module paths (`tool/lighttool.toml`, `tool/build.gradle.kts`, `tool/src/main/kotlin/**`, resources/assets) and compiling against a **pinned official SDK** offline. Approval for the curated tier weighs "whether a submitted tool matches the Light ethos both functionally and aesthetically." Metadata contract: strict semver `versionName` (no pre-release/build metadata), strictly increasing `versionCode`, permission allow-list.
- **Trust tiers** (discussion #93): Light-released → Light-signed + community library (the default users keep) → Light-signed only → any APK. Dashboard install ETA: "rough estimate: late august?" (#121).
- **De facto sharing today:** post in [Discussions → Tools](https://github.com/orgs/lightphone/discussions/categories/tools) with screenshots + repo link; PR onto [awesome-light](https://github.com/garado/awesome-light) (the unofficial directory, discussion #110); Discord #Developers. Users sideload via developer mode (tolerated, unsupported, may break without notice — #70).
- **Dominant community pattern:** fork-per-tool, repo renamed to the tool, app code in `tool/` (e.g. `wildassoler/pomodoro-light`, `ChopinDavid/recall-lightos`). Builder docs: "Most Light SDK tools will be forks of this repo with edits to the `tool/` module." Standalone non-fork repos are equally viable (`trentcowden/bible-tool`, `maja83-collab/fold-light`) — the builder consumes (git URL, commit), not fork metadata.
- **SDK contributions are issue-first, hard rule** — PRs without a green-lit issue get closed. Welcome: bug reports, feature requests, **allow-list additions** (libraries/permissions — merged precedent exists, #40→#44). Not welcome: public API changes, architecture changes. **AI/LLM policy:** all communication human-written; you are responsible for everything from your account; no automated/LLM-branded PRs.
- **Build requirement:** GitHub token with `read:packages` (artifacts on GitHub Packages; JitPack migration planned, issue #80).

### The fork (`tyleryancey/light-tools`)

- 20 branches: 5 tool branches, 2 bot-made `sync/*` conflict-parking branches, `main`, 12 stale inherited upstream branches (all still exist upstream; deletable).
- **Topology inverted:** fork `main` is 19 commits / 77 files behind upstream while `ringtone-studio` merged `upstream/main` directly and is fully current — the hub is staler than a spoke.
- **Structural conflict class:** all five tool branches overwrite the same `tool/` module, so every upstream touch of `tool/` conflicts with all branches, permanently. The sync bot committed **raw conflict markers** into `sync/main-into-{sudoku,ledger}`; their PRs (#3, #4) show `mergeable=true` with only a red CI check preventing broken merges. `sync/main-into-sudoku` is also stale (would revert v1.3.1/v1.3.2).
- **Zero PRs ever sent upstream**, but sudoku carries genuine SDK fixes (safe-drawing insets to `LightActivity.kt`/`LightScreen.kt`) that pending upstream changes will collide with.
- Releases: 5 (all Sudoku, latest v1.3.2); tags `sudoku-v*`, `tides-v0.1.0`, inherited `v0.0.x`. Chess (submission-ready), ringtone-studio (device-verified), ledger have no releases.

### Local (`~/Documents/lightphone`)

- Three object stores: `light-tools` (clone, hosts worktrees `-correspondence-chess`, `-ledger`, `-ringtone-studio`; the ringtone worktree is registered under the mismatched name `rt-worktree`); `light-tools-tides` (independent second clone of the same remote); `light-sdk` (pristine upstream clone, never built).
- **At-risk work:** `ledger` 28 commits ahead of origin, unpushed, objects living in `light-tools/.git`; `light-tools-sun-and-moon/CLAUDE-sun-and-sky.md` (complete tool spec, no version control, single copy); four `Untitled_*` scratchpads (incl. the sync-conflict resolution recipe, misnamed `Untitled_chess`); gitignored `.superpowers/sdd/` briefs+review diffs, `.remember/` logs, `local.properties`, `sdk/emulator/keys/`.
- Chess worktree dirty: `settings.gradle.kts` (foojay plugin block) + `lighttool.toml` (`serverPackage` → `com.lightos` device flip) + untracked `gradle-daemon-jvm.properties`.
- ~2.3 GB of ~3.1 GB is regenerable build output. Out of scope but flagged: `~/Documents/light-phone-3-lightos-dev/` (1.5 GB, third remote `tyleryancey/light-sdk-sudoku-port`), `lightphone.zip` (755 MB), `light-tools-tides.zip` (79 MB).

## 4. Design

### 4.1 GitHub account structure

| Repo | Role |
|---|---|
| `light-sudoku`, `light-tides`, `light-ledger`, `light-chess`, `light-ringtone-studio` | One standalone **public** repo per tool. `main` = prod pointer = submission artifact. Own issues, releases, README, topics (`lightphone`, `lightos`, `light-sdk`). Created by pushing the existing tool branch — full history (SDK ancestry) preserved so `upstream` merges keep working. |
| `light-sdk` | The GitHub **fork** of `lightphone/light-sdk` (renamed from `light-tools`; renames redirect). Reserved for upstream contributions only: `main` mirrors upstream (never committed to), `fix/*`/`feat/*` branches per green-lit issue. GitHub permits one fork per account — this is its one job. |
| `light-workspace` | **Public.** Reusable upstream-sync workflow, cross-tool conventions/docs (`SYNCING.md`, QA checklist, PR template source), specs for unstarted tools (Sun & Sky), rescued scratchpads. Anything truly private stays local or in a separate private repo (decided per item at migration). |

Future tools start as a fresh repo scaffolded from upstream `main` plus their spec from `light-workspace`.

### 4.2 Per-tool repo model (dev → qa → prod)

- **Branches:** `main` (protected: PR + green CI required) plus short-lived `feat/*` / `fix/*` (upstream's naming convention). Dev iteration on the emulator happens on feature branches.
- **CI (GitHub Actions):**
  - `pr-check.yml` (inherited): `./gradlew check` on every PR.
  - `release.yml` (new): on tag `v*` — build APK, create GitHub Release, attach APK.
  - `sync.yml` (new, ~10 lines): calls the reusable workflow from `light-workspace` (weekly cron + `workflow_dispatch`).
  - Repo secret: GitHub token with `read:packages` for SDK artifacts.
- **QA gate:** before merging a release-worthy PR, install that branch's build on the physical LP3 via Android Studio and exercise it; QA checklist lives in the PR template. Each repo carries a `run-<tool>` Claude Code skill (modeled on the existing `run-ringtone-studio`) so device deploy is one command. Device config (`serverPackage = com.lightos`) is committed, as tides already does.
- **Releases:** merge → tag `vX.Y.Z` on `main` (plain semver, no tool prefix, no `-rc` suffixes — the builder rejects pre-release metadata in `versionName`; `versionCode` strictly increases). `release.yml` publishes the APK.
- **Submission readiness:** each repo maintains `SUBMISSION.md` (fold-light format: tool id, version/versionCode, commit SHA, build command, permissions, testing notes) so official submission is copy-paste when the front door opens.
- **Sharing today:** GitHub Release URL + post in Discussions → Tools + PR to awesome-light.

### 4.3 SDK sync strategy

Reusable workflow in `light-workspace`, called per tool repo:

1. Fetch `upstream/main`; attempt merge on `sync/upstream-<date>` with a merge driver configured so conflicts under `tool/**` auto-resolve **"ours"** (the tool module always wins over upstream's sample edits). This eliminates the recurring `lighttool.toml` conflict class mechanically.
2. Merge completes → push branch, open PR to `main`; CI runs; human reviews and merges. **Conflict markers can never be committed.**
3. Genuine conflicts remain (patched SDK files outside `tool/`) → abort the merge; open a PR from a clean branch pinned at `upstream/main` with a comment listing conflicted files; resolve locally per `SYNCING.md` (formalized from the `Untitled_chess` recipe: keep the branch's tool identity, semver-ify `versionName`, honor sample-file deletions).

The pristine local `light-sdk` vendor clone is retired; the fork's mirrored `main` is the reference copy.

### 4.4 Upstream contribution flow

- Fork `main`: fast-forward from upstream only.
- Process: file issue → wait for explicit maintainer green light → branch `fix/<thing>` → `./gradlew check` → PR. Upstream work is the slow lane and never blocks tool work: the tool repo carries the patch until upstream lands it; the next sync then supersedes the local copy.
- AI-policy compliance: all text sent to `lightphone/*` is written by Tyler in his own words; Tyler reviews and can explain every line submitted; Claude assists locally only.
- First candidate: the safe-drawing-insets fix (`LightActivity.kt`/`LightScreen.kt`) currently in the sudoku branch.

### 4.5 Local machine layout

```
~/Documents/lightphone/
  light-sdk/               fork clone (origin=tyleryancey/light-sdk, upstream=lightphone/light-sdk)
  light-sudoku/            clone of tyleryancey/light-sudoku
  light-tides/             clone of tyleryancey/light-tides
  light-ledger/            clone of tyleryancey/light-ledger
  light-chess/             clone of tyleryancey/light-chess
  light-ringtone-studio/   clone of tyleryancey/light-ringtone-studio
  light-workspace/         clone of tyleryancey/light-workspace
```

- One folder = one repo = one Android Studio project = one Claude Code session; folder names equal repo names. No worktrees (obsolete under repo-per-tool).
- Per-repo `CLAUDE.md`, `00-ASSESSMENT.md`, `run-<tool>` skill; shared conventions once in `light-workspace`.
- Gitignored precious state (`.superpowers/sdd/`, `.remember/`, `local.properties`, emulator keys) is migrated folder-to-folder, never dropped.
- Cost: each built tree ~0.5 GB regenerable Gradle output; periodic `./gradlew clean` in idle projects.

## 5. Migration plan (safety-first; nothing deleted until verified)

1. **Secure at-risk work:** push `ledger` (28 commits); commit chess's device-config tweaks; create `light-workspace` and commit the Sun & Sky spec + all four `Untitled_*` scratchpads.
2. **Defuse hazards:** close fork PRs #3/#4; delete `sync/main-into-sudoku` and `sync/main-into-ledger` (committed conflict markers; superseded by §4.3).
3. **Create the five tool repos:** push each tool branch as new repo `main`; re-create tags under the plain `vX.Y.Z` convention pointing at the same commits (sudoku-v1.1…v1.3.2 → v1.1.0…v1.3.2; tides-v0.1.0 → v0.1.0; tags do not transfer automatically and are being renamed anyway); recreate the 5 sudoku GitHub Releases with their APK assets downloaded from the fork first; add `upstream` remotes, the three workflows, `read:packages` secret, branch protection, topics/descriptions, `SUBMISSION.md` where missing.
4. **Re-point local folders:** convert each worktree/clone into a standalone clone of its new repo; rename folders to match repo names; carry over gitignored precious state. Re-point the vendor `light-sdk` clone at the renamed fork (origin=tyleryancey/light-sdk, upstream=lightphone/light-sdk), preserving its untracked `CLAUDE.md`.
5. **Clean the fork** (only after 3–4 verified): delete tool branches, delete the 12 inherited branches, reset `main` to upstream, remove old sync workflow, rename `light-tools` → `light-sdk`, update description.
6. **Verify:** every repo `./gradlew check` green; releases intact; every folder opens in Android Studio; worktree removal left no stale registrations.
7. **Aftercare (per-item user decision):** archive/delete `light-sdk-sudoku-port` + `~/Documents/light-phone-3-lightos-dev/`; delete stale snapshot zips; gradle-clean sweep (~2.3 GB); file the insets issue upstream; add unshared tools to Discussions → Tools and awesome-light.

**Rollback:** steps 1–4 are purely additive; until step 5 the old fork still contains everything.

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Losing the 28 unpushed ledger commits during folder moves | Step 1 pushes before anything moves; worktree objects live in `light-tools/.git`, so no folder is moved/renamed before step 4 |
| Sync PRs #3/#4 merged by accident before cleanup | Step 2 closes them early |
| Release recreation loses APK assets | Download assets first; verify new releases before deleting old tags/releases from the fork |
| Upstream changes builder contract (pre-1.0, "things will change fast") | `SUBMISSION.md` + strict adherence to `tool/`-only edits keeps surface minimal; sync PRs surface contract changes weekly |
| GitHub rename breaks local remotes | Renames redirect; local remotes updated in step 4 anyway |
| Reusable-workflow visibility | `light-workspace` is public, satisfying the public-caller requirement |

## 7. Out of scope

- Implementing any tool feature work (sudoku TODOs from `Untitled_sudoku2`, tides v0.2 roadmap, Sun & Sky build-out).
- Resolving the old `sync/*` conflicts (branches are deleted, not resolved; each new repo syncs freshly from upstream).
- Discord/awesome-light promotion beyond the aftercare checklist.
- The `light-phone-3-lightos-dev` folder's `sudoku-port` branch contents (flagged for user review in aftercare).
