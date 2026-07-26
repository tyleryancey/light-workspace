---
name: workspace-health
description: Read-only cross-repo health sweep of the Light Phone workspace (~/Documents/lightphone/light-*) — unpushed commits that exist on no remote, open sync/upstream-* PRs silently blocking all future syncs, red or auto-disabled GitHub Actions workflows, upstream/main drift, serverPackage drift, and gitignored local-only state. Use this whenever asked to check the state of my repos, what's unpushed, workspace status, whether anything is broken across my tools, whether any CI went red, for a weekly check-in, or "what was I working on" — and before any release, sync, or cleanup that assumes a clean workspace.
---

# Workspace health

## Run it

```bash
bash ~/.claude/skills/workspace-health/scripts/health.sh          # default root: ~/Documents/lightphone
bash ~/.claude/skills/workspace-health/scripts/health.sh /some/other/root
```

That path assumes the install symlink exists:
`ln -s ~/Documents/lightphone/light-workspace/skills/workspace-health ~/.claude/skills/workspace-health`
(the installation step — see **Placement** below). If it is missing, run
`scripts/health.sh` from this skill's own directory instead.

Takes ~15s (one PR list, one workflow list, one run list per GitHub repo). Read
the whole output, then relay the **needs-attention** section — not the table.

## Why this skill exists

A real audit of this workspace found **28 unpushed commits** in a repo whose
working tree was perfectly clean. The objects lived in a shared `.git`, the
checked-out branch was in sync with its remote, and `git status` said nothing.
Nothing in day-to-day use surfaced them. Losing that directory would have cost a
full code-review remediation pass.

**The value of this sweep is catching the invisible, not restating what
`git status` already shows.** Every check below earns its place by covering
something no single-repo command tells you. If you find yourself reporting
"working tree clean" as a result, you have missed the point.

A corollary that is a design requirement, not a preference: **a sweep that
prints forty green lines and buries one red one has failed at its job.** The
script prints a compact one-row-per-repo table, then a needs-attention section
containing *only* actionable findings, most severe first. When nothing is wrong
it prints one `All clear` line rather than a section header with nothing under
it. Preserve that shape if you edit the script.

## What it checks, and why each matters

**1. Current branch and dirty tree** — counted as `Nm/Nu` (modified/untracked).
Untracked files are counted separately and deliberately: a forgotten new file is
as losable as an uncommitted edit, and `git status -uno` hides it. Stash entries
are flagged too; stashes exist only on this disk.

**2. Commits that exist on NO remote** (`git rev-list --count --all --not --remotes`).
The headline check, and the one the 28-commit incident was about. Note this is a
**superset** of the `@{u}..HEAD` check, and the superset is the whole point: in
that incident the checked-out branch was clean and in sync, so `@{u}..HEAD` said
`0` while a *different* branch in the same `.git` held the commits. Reported as
`N LOCAL` in the table, with the holding branch named and marked when it is not
the checked-out one. Do not "simplify" this back to the current branch.

**3. Every local branch ahead of its own upstream** — via one
`git for-each-ref` over `refs/heads`, with exact counts from
`git rev-list --left-right --count`, per branch, not just HEAD. Distinct from
check 2 and less severe: those commits need a push but already exist on some
remote ref. Also catches branches with **no upstream at all** and branches whose
upstream was **deleted** (`[gone]`) — both states where nothing is tracking your
work, so nothing warns you about it.

**4. Behind its own origin** — stale local checkout; pull before working.

**5. Behind `upstream/main`**, for repos with an `upstream` remote — accumulated
SDK drift. **The count is only as fresh as the last fetch**, so the fetch age
(mtime of `.git/FETCH_HEAD`) travels inline with the number: `19 @7h`. A missing
`FETCH_HEAD` reports `never fetched`, because unknown drift is not zero drift.
The script never fetches; report staleness rather than silently refreshing.

**6. Open PRs, with `sync/upstream-*` heads called out** — these are not just
open PRs. An open sync PR **blocks all future syncs in that repo**: the sync
workflow's `OPEN_SYNC` guard (`.github/workflows/reusable-sync.yml`) counts open
PRs whose head starts with `sync/upstream-` and skips the run while any exists.
That is a silent stoppage. Marked `!SYNC` in the PRS column and raised as its own
severity tier. Hand these to the **`sync-resolve`** skill; see
`light-workspace/docs/SYNCING.md`. Closing the bot's PR is what releases the
guard.

**7. Latest run conclusion per workflow** — the single best proxy for a whole
class of invisible failures. An expired PAT, a revoked token, a broken shared
workflow: none of these announce themselves, they just turn runs red on a
schedule nobody watches. Prefer this over trying to read token expiry directly —
the tokens are Actions secrets, so **nothing local can inspect them**. A red
scheduled run is the signal you get.

**8. Workflows GitHub has auto-disabled** — any workflow whose `state` is not
`active`. GitHub disables scheduled workflows after roughly 60 days of repo
inactivity, which silently stops syncing on a quiet tool. Re-enable from the
repo's Actions tab. Also flags a **scheduled** workflow with zero runs, for the
same reason.

One known gap in the zero-runs half: deciding whether a workflow is scheduled
means reading its YAML off a specific clone's disk, while findings are emitted
once per *canonical* GitHub repo. When several directories share one repo — the
rename-redirect case above — whichever directory claims the finding first is the
one whose disk gets read. If that happens to be a legacy clone that predates the
workflow, the check sees no `schedule:` trigger and drops the finding rather than
misattributing it. Directory order makes this unlikely today, but if a scheduled
workflow you know exists never appears here, check it directly in the Actions tab
rather than trusting the silence.

Deliberately *not* flagged, because it is noise rather than signal: a
tag-triggered `release.yml` that has never run (no release yet), and a
`workflow_call`-only reusable workflow with no runs (its runs are attributed to
the caller repo, so it will never have any of its own).

**9. `serverPackage` in `tool/lighttool.toml`** — should commit `com.lightos`.
Extracted with an anchored `sed` so a commented-out alternate is skipped, and
with `[^"]*` so a trailing quoted comment cannot be swallowed into the value.
Three distinct states, and the distinction matters:

- working tree ≠ HEAD → **modified locally**, a legitimate temporary state for
  AVD work. Reported as such, with `git checkout -- tool/lighttool.toml` to
  restore — not as an error. Still flagged, because forgetting to restore it is
  exactly how these repos once drifted apart.
- committed value ≠ `com.lightos` → real drift.
- `light-sdk` is exempt from the second case: as the fork mirroring upstream
  `lightphone/light-sdk` it commits the emulator value by design. The exemption
  is keyed on origin's own URL, not on the canonical repo name, so a repo rename
  cannot silently exempt a directory that genuinely drifted.

**10. Gitignored-but-precious local state** — `.superpowers/`, `.remember/`,
`local.properties`, `sdk/emulator/keys/`. Invisible to `git status` by design,
living in exactly one place. These are what a "clean tree, safe to delete"
reading gets wrong. **Presence is reported, never contents.**

## Discovery: glob, never a hardcoded list

Repos are found by globbing `$WORKSPACE/light-*`, so a new tool is covered the
day it is created. Expect `light-sdk` (the fork mirroring upstream
`lightphone/light-sdk`), `light-workspace` (shared CI and docs), and the tool
repos `light-{sudoku,chess,ledger,ringtone-studio,tides}`.

**Do not filter the glob down to that expected list.** Globbing exists precisely
to surface what a hardcoded list would miss, and it currently finds three
directories the list does not mention — including `light-tools`, a legacy
pre-split clone holding 5 commits on `main` that are not on `origin/main`, which
is invisible because its checked-out branch is `sudoku` and clean. That is the
28-commit pattern, live in the workspace today.

Handled without erroring: a `light-*` directory that is not a repo at all (one
row, `(not a git repo)`, no attention entry), `.git` as a *file* rather than a
directory (worktrees/submodules — the repo test is `git rev-parse --git-dir`, not
`[ -d .git ]`), and detached HEAD.

## Operational rules

**This skill is strictly read-only.** No pushes, no PR or branch creation, no
`git fetch` — fetching rewrites remote-tracking refs and would change the very
numbers being measured. Report staleness instead. If you ever add a fetch, note
it explicitly in the output.

**`lightphone/*` is strictly read-only.**

**Pass `-R <owner>/<repo>` to every `gh` call.** Each clone has an `upstream`
remote pointing at `lightphone/light-sdk`, and with no default set `gh` can
resolve the base repo to **upstream** — producing misleading output and, for any
write, aiming at a repo that must stay read-only. It has failed closed before;
do not rely on that.

**Derive `owner/repo` from `git remote get-url origin`, never from the directory
name.** In this workspace `light-tools-tides`' origin is `tyleryancey/light-tools`,
so name-derivation would query a repo that does not exist. The script goes one
step further and resolves each slug to its canonical `full_name`, because GitHub
redirects renamed repos: `tyleryancey/light-tools` now redirects to
`tyleryancey/light-sdk`, so three directories share one GitHub repo and therefore
one set of PR/CI results. That is surfaced as a finding rather than left to
confuse you, and it dedupes the API calls.

If `gh` is missing or unauthenticated, the PR, sync-block and CI columns show
`n/a` and the script says so once at the end. Those are the checks nothing local
can substitute for — fix `gh` and re-run rather than reporting a clean sweep.

## Reading the output

Severity tiers, in the order they print:

1. **UNPUSHED — exists nowhere else.** Data loss risk. Push or back up now.
2. **UNPUSHED — ahead of its own remote.** Needs a push; recoverable.
3. **BLOCKED SYNC.** An open `sync/upstream-*` PR; syncs are stopped until it
   closes. Use `sync-resolve`.
4. **CI / PRs.** Red runs, auto-disabled workflows, unreachable origins.
5. **UPSTREAM DRIFT.** Behind `upstream/main`, with fetch age attached.
6. **serverPackage.** Local modification or committed drift.
7. **LOCAL STATE.** Dirty tree, stashes, stale checkout.

Tiers are attached to findings as a sort key and sorted at print time, so adding
a check never disturbs the ordering. Keep it that way.

## Placement

Installed at **user level**, symlinked from `light-workspace/skills/` into
`~/.claude/skills/`, because it spans repos and must be invocable from anywhere —
unlike the per-repo skills. Consequently the script **must not assume the current
working directory is a repo**: it takes the workspace root as `$1`, defaulting to
`~/Documents/lightphone`, and addresses every repo with `git -C`. Do not add
logic that depends on `cd` or on being launched inside a clone.
