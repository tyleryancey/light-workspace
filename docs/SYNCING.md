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
4. `./gradlew check`, then push `resolve-sync` and open a **new** PR from it to
   `main` — a PR's head branch cannot be retargeted. Close the bot's sync PR
   (closing is what releases the guard below; deleting its branch is just
   hygiene) once the new PR is open.

Never commit conflict markers. If in doubt, abort (`git merge --abort`) and ask for review.

A conflicting sync PR shows **no check runs at all** — GitHub can't build a
merge ref for a conflicting PR, so `pull_request` workflows never fire. That's
expected, not a sign CI is broken.

An open `sync/upstream-*` PR blocks all future syncs in this repo (the sync
workflow's `OPEN_SYNC` guard skips runs while one exists), so resolving
promptly matters.

## Always pass `-R <owner>/<repo>` to `gh` in a repo with an `upstream` remote

Every tool clone (and the sync job, which adds the remote itself) has
`upstream` → `lightphone/light-sdk` alongside `origin`. With no default set,
`gh` may resolve the **base repo to upstream**, so `gh pr create` tries to open
the PR against `lightphone/light-sdk` and fails with a misleading
`No commits between main and <branch>` / `Head sha can't be blank`. That error
is base-repo misresolution, not indexing lag and not a bad branch.

Two consequences:

- Pin every `gh` invocation: `gh pr create -R tyleryancey/light-<tool> ...`.
  (Or set a default once per clone with `gh repo set-default`.)
- **This is also a safety issue** — had such a call succeeded it would have
  opened a PR on an upstream repo we treat as read-only. It failed closed, but
  don't rely on that.

The sync workflow is already immune: its `gh api "repos/${GITHUB_REPOSITORY}/..."`
calls name the repo explicitly, which is the real reason switching the sync PR
creation from `gh pr create` to the REST API fixed it. `reusable-release.yml`'s
`gh release create` is safe today only because that job never adds an `upstream`
remote — pin it with `-R "$GITHUB_REPOSITORY"` if that ever changes.
