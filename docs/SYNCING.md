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
