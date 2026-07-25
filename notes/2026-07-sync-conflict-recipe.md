/btw how to handle the conflicted merges of the same upstream changes for PRs #3 and #4?

    Both PRs hold the same conflict shape chess had, so the chess resolution is your template. Two files conflict:

    1. tool/lighttool.toml — upstream changed the sample to versionName = "1.0.0" and permissions = ["android.permission.INTERNET"], colliding with each branch's rewritten toml. Resolution: keep the branch's own identity (its id, label, and its own permissions list — don't inherit the sample's INTERNET permission), and bump versionName to valid semver, since upstream's builder now enforces x.y.z. For sudoku that likely means "1.3" → "1.3.0" (matching the sudoku-v1.3 tag); for ledger, whatever its current version is, semver-ified. Leave versionCode alone.
    2. tool/src/main/kotlin/com/thelightphone/sample/HomeScreen.kt — modify/delete: your branches deleted the sample, upstream modified it. Keep the deletion (git rm it).

    Two ways to execute, per branch:

    Option A — redo the merge cleanly on the branch itself (what I did for chess, and cleaner history):
    # sudoku: in ~/Documents/lightphone/light-tools (already on sudoku)
    # ledger: in ~/Documents/lightphone/light-tools-ledger
    git fetch origin
    git merge origin/main
    # fix tool/lighttool.toml as above, then:
    git rm tool/src/main/kotlin/com/thelightphone/sample/HomeScreen.kt
    git add tool/lighttool.toml
    git commit
    ./gradlew check        # catches the semver enforcement and anything else
    git push origin sudoku   # or ledger
    Then close the PR (gh pr close 3 / 4) and delete its sync branch (git push origin --delete sync/main-into-sudoku / -ledger). The PR becomes redundant because the branch already contains the clean merge.

    Option B — resolve inside the PR, as its body suggests: check out sync/main-into-sudoku (it contains the merge commit with conflict markers committed in the files), edit the files to remove the markers with the same resolutions, commit, push to the sync branch, then merge the PR with a merge commit (not squash). Functionally equivalent, but leaves a conflicted commit plus a fixup in history.

    Two caveats: I verified this conflict shape directly only on chess — all three legs failed identically, but ledger has ~68 branch commits, so glance at git status after the merge in case it picked up an extra conflict beyond those two files. And run ./gradlew check before pushing either branch — that's what proves the semver bump satisfies the new builder enforcement.

      Once each PR is closed or merged, the Monday sync resumes for that branch automatically (the workflow only skips branches while their conflict PR is open). 