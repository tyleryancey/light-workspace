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
