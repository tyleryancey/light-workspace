#!/usr/bin/env bash
# workspace-health -- read-only cross-repo status sweep of the Light Phone workspace.
#
# Surfaces the things that are INVISIBLE in day-to-day use: commits that exist on
# no remote, an open sync PR silently blocking all future syncs, workflows GitHub
# auto-disabled, red scheduled runs nobody watches, gitignored local-only state.
#
# STRICTLY READ-ONLY. No fetch, no push, no PR/branch/ref writes. Every gh call is
# a GET and is pinned with -R <owner>/<repo> derived from origin's URL, because each
# clone has an `upstream` remote pointing at lightphone/light-sdk (read-only) and an
# unpinned gh can resolve the base repo to upstream.
#
# Usage: health.sh [workspace-root]     (default: ~/Documents/lightphone)

set -u
set -o pipefail

WORKSPACE="${1:-$HOME/Documents/lightphone}"
EXPECTED_PKG="com.lightos"
NOW=$(date +%s)

if [ ! -d "$WORKSPACE" ]; then
  echo "workspace-health: no such directory: $WORKSPACE" >&2
  exit 1
fi

CACHE=$(mktemp -d "${TMPDIR:-/tmp}/wshealth.XXXXXX") || exit 1
trap 'rm -rf "$CACHE"' EXIT INT TERM
FINDINGS="$CACHE/findings"
LOCALSTATE="$CACHE/localstate"
: > "$FINDINGS"
: > "$LOCALSTATE"

# Severity tiers. Findings are emitted with a tier and sorted at print time, so
# adding a check never disturbs the ordering. Lowest number = most severe.
S_UNPUSHED=1   # commits on NO remote -- only copy is this disk
S_AHEAD=2      # branch ahead of its own upstream (recoverable, still needs a push)
S_SYNCBLOCK=3  # open sync/upstream-* PR: blocks ALL future syncs in that repo
S_CI=4         # failing / auto-disabled / never-run workflows
S_DRIFT=5      # behind upstream/main
S_TOML=6       # serverPackage not the committed value
S_TREE=7       # dirty tree, behind own origin

note() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$FINDINGS"; }

age_human() {
  s=$1
  if [ "$s" -lt 3600 ]; then echo "$((s / 60))m"
  elif [ "$s" -lt 86400 ]; then echo "$((s / 3600))h"
  else echo "$((s / 86400))d"; fi
}

mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# --- gh availability -----------------------------------------------------------
GH_OK=no
GH_WHY=""
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then GH_OK=yes; else GH_WHY="gh is not authenticated (run: gh auth login)"; fi
else
  GH_WHY="gh CLI not installed -- PR and CI columns unavailable"
fi

# owner/repo from origin's URL. NEVER from the directory name: light-tools-tides'
# origin is tyleryancey/light-tools, so name-derivation would query a repo that
# does not exist.
repo_slug() {
  _u=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  case "$_u" in *github.com*) ;; *) return 1 ;; esac
  _s=${_u##*github.com}
  _s=${_s#:}; _s=${_s#/}; _s=${_s%.git}; _s=${_s%/}
  case "$_s" in */*) printf '%s\n' "$_s" ;; *) return 1 ;; esac
}

# One PR-list + one workflow-list + one run-list per GitHub repo, cached by slug so
# two directories sharing an origin cost one round trip.
gh_load() {
  _slug=$1
  _key=$(printf '%s' "$_slug" | tr '/' '_')
  [ -f "$CACHE/done_$_key" ] && return 0
  : >"$CACHE/pr_$_key"; : >"$CACHE/wf_$_key"; : >"$CACHE/run_$_key"
  gh pr list -R "$_slug" --state open --limit 50 \
    --json number,headRefName,title \
    --jq '.[]|[.number,.headRefName,.title]|@tsv' >"$CACHE/pr_$_key" 2>/dev/null
  gh api "repos/$_slug/actions/workflows" --paginate \
    --jq '.workflows[]|[.state,.name,.path]|@tsv' >"$CACHE/wf_$_key" 2>/dev/null
  # newest run per workflow in a single call (grouping in jq keeps us bash-3.2 safe)
  gh run list -R "$_slug" --limit 100 \
    --json workflowName,conclusion,status,createdAt,url \
    --jq 'group_by(.workflowName)|map(max_by(.createdAt))|.[]|[.workflowName,(.conclusion//"-"),.status,.url]|@tsv' \
    >"$CACHE/run_$_key" 2>/dev/null
  : >"$CACHE/done_$_key"
}

# GitHub redirects a renamed repo, so origin's URL can name a repo that no longer
# exists under that name. Resolve to the canonical full_name: it dedupes the API work
# when several clones share one repo, and a mismatch is itself worth reporting.
canonical_slug() {
  _k=$(printf '%s' "$1" | tr '/' '_')
  if [ ! -f "$CACHE/canon_$_k" ]; then
    gh api "repos/$1" --jq '.full_name' >"$CACHE/canon_$_k" 2>/dev/null || : >"$CACHE/canon_$_k"
  fi
  head -1 "$CACHE/canon_$_k"
}

# "Never run" is only a finding for SCHEDULED workflows -- those are the ones that
# stop silently. A tag-triggered release.yml that has never run just means no release
# yet, and a workflow_call-only reusable workflow never runs standalone at all: its
# runs are attributed to the caller repo. Neither is a problem; both are pure noise.
is_scheduled() {
  [ -f "$1" ] || return 1
  grep -qE '^[[:space:]]*schedule:' "$1" 2>/dev/null
}

trunc() { # trunc <string> <width>
  if [ ${#1} -le "$2" ]; then printf '%s' "$1"; else printf '%s…' "$(printf '%s' "$1" | cut -c1-$(($2 - 1)))"; fi
}

# --- table header --------------------------------------------------------------
ROW_FMT='%-21s %-24s %-9s %-11s %-8s %-14s %-5s %s\n'
echo "Light Phone workspace health -- $WORKSPACE"
echo "$(date '+%Y-%m-%d %H:%M')  (read-only: nothing was fetched, pushed, or changed)"
echo
# shellcheck disable=SC2059
printf "$ROW_FMT" REPO BRANCH TREE UNPUSHED BEHIND UPSTREAM PRS CI
printf '%s\n' "---------------------------------------------------------------------------------------------------------------"

REPO_COUNT=0
for dir in "$WORKSPACE"/light-*; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")

  # .git can be a file (worktree/submodule), so ask git rather than testing for a dir
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    # shellcheck disable=SC2059
    printf "$ROW_FMT" "$(trunc "$name" 21)" "(not a git repo)" - - - - - -
    continue
  fi
  REPO_COUNT=$((REPO_COUNT + 1))
  gitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)

  # 1. branch + working tree (untracked counted separately: a forgotten new file is
  #    as losable as an uncommitted edit, and `git status -uno` hides it)
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch="(detached)"
  mod=$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null | grep -c . | tr -d ' ')
  untr=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null | grep -c . | tr -d ' ')
  if [ "$mod" -eq 0 ] && [ "$untr" -eq 0 ]; then
    tree_cell="clean"
  else
    tree_cell="${mod}m/${untr}u"
    _d=""
    [ "$mod" -gt 0 ] && _d="$mod modified"
    [ "$untr" -gt 0 ] && _d="${_d:+$_d, }$untr untracked"
    note "$S_TREE" "$name" "working tree dirty: $_d (on $branch)"
  fi
  stashes=$(git -C "$dir" stash list 2>/dev/null | grep -c . | tr -d ' ')
  [ "$stashes" -gt 0 ] && note "$S_TREE" "$name" "$stashes stash entr$([ "$stashes" -eq 1 ] && echo y || echo ies) -- stashes live only here"

  # 2. THE headline check. Commits reachable from any local ref but from no remote
  #    ref exist ONLY on this disk. This is the check the 28-commit incident was
  #    about: that repo's checked-out branch was clean and in sync, so @{u}..HEAD
  #    said 0 while another branch in the same .git held the commits.
  nowhere=$(git -C "$dir" rev-list --count --all --not --remotes 2>/dev/null) || nowhere=0
  [ -z "$nowhere" ] && nowhere=0
  if [ "$nowhere" -gt 0 ]; then
    unpushed_cell="${nowhere} LOCAL"
    note "$S_UNPUSHED" "$name" "$nowhere commit(s) exist on NO remote -- only copy is $gitdir. Losing this directory loses them."
    git -C "$dir" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | while read -r br; do
      [ -n "$br" ] || continue
      c=$(git -C "$dir" rev-list --count "$br" --not --remotes 2>/dev/null)
      [ -n "$c" ] && [ "$c" -gt 0 ] && note "$S_UNPUSHED" "$name" "  branch '$br' holds $c of them$([ "$br" = "$branch" ] || echo ' (NOT the checked-out branch)')"
    done
  else
    unpushed_cell="-"
  fi

  # 2b/3. Per-branch ahead/behind for EVERY local branch, not just HEAD -- the
  #       non-checked-out branch is the one nothing else surfaces. Exact counts come
  #       from rev-list; %(upstream:track) text is localized and not parsed.
  head_ahead=0; head_behind=0; behind_cell="-"
  git -C "$dir" for-each-ref --format='%(refname:short)|%(upstream:short)|%(upstream:track)' refs/heads 2>/dev/null >"$CACHE/branches"
  while IFS='|' read -r br up track; do
    [ -n "$br" ] || continue
    case "$track" in
      *gone*)
        note "$S_AHEAD" "$name" "branch '$br' tracks $up which no longer exists on the remote (deleted upstream)"
        continue ;;
    esac
    if [ -z "$up" ]; then
      note "$S_AHEAD" "$name" "branch '$br' has no upstream -- nothing is tracking it, so nothing warns you about it"
      continue
    fi
    git -C "$dir" rev-parse --verify --quiet "$up" >/dev/null 2>&1 || continue
    lr=$(git -C "$dir" rev-list --left-right --count "$up...$br" 2>/dev/null) || continue
    bh=$(printf '%s' "$lr" | awk '{print $1}')
    ah=$(printf '%s' "$lr" | awk '{print $2}')
    [ -z "$bh" ] && bh=0
    [ -z "$ah" ] && ah=0
    if [ "$br" = "$branch" ]; then
      head_ahead=$ah; head_behind=$bh
      [ "$bh" -gt 0 ] && behind_cell="$bh"
    fi
    if [ "$ah" -gt 0 ]; then
      if [ "$br" = "$branch" ]; then
        note "$S_AHEAD" "$name" "'$br' is $ah commit(s) ahead of $up -- unpushed"
      else
        note "$S_AHEAD" "$name" "'$br' is $ah commit(s) ahead of $up -- unpushed, and it is NOT the checked-out branch so git status never mentions it"
      fi
    fi
    if [ "$bh" -gt 0 ] && [ "$br" = "$branch" ]; then
      note "$S_TREE" "$name" "checked-out '$br' is $bh commit(s) behind $up -- stale local checkout, pull before working"
    fi
  done <"$CACHE/branches"
  [ "$unpushed_cell" = "-" ] && [ "$head_ahead" -gt 0 ] && unpushed_cell="${head_ahead} ahead"

  # 4. SDK drift against upstream/main -- only as fresh as the last fetch, so the
  #    age travels WITH the number instead of being reported as if it were current.
  up_cell="-"
  if git -C "$dir" rev-parse --verify --quiet upstream/main >/dev/null 2>&1; then
    base=main; base_label=main
    if ! git -C "$dir" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then
      base=HEAD; base_label="$branch (no local main)"
    fi
    drift=$(git -C "$dir" rev-list --count "$base..upstream/main" 2>/dev/null) || drift=""
    if [ -f "$gitdir/FETCH_HEAD" ]; then
      fm=$(mtime_of "$gitdir/FETCH_HEAD")
      if [ -n "$fm" ]; then fage=$(age_human $((NOW - fm))); else fage="?"; fi
    else
      fage="never"
    fi
    if [ -n "$drift" ]; then
      up_cell="$drift @${fage}"
      if [ "$drift" -gt 0 ]; then
        note "$S_DRIFT" "$name" "$base_label is $drift commit(s) behind upstream/main (as of a fetch $fage ago -- re-fetch to confirm)"
      fi
    fi
    case "$fage" in
      never) note "$S_DRIFT" "$name" "upstream remote configured but never fetched -- upstream drift is unknown, not zero" ;;
      *d) [ "${fage%d}" -ge 7 ] && note "$S_DRIFT" "$name" "last fetch was $fage ago -- every remote number below is at least that stale" ;;
    esac
  fi

  # 5/6/7. GitHub side: open PRs (sync PRs are special), latest run per workflow,
  #        auto-disabled workflows. All GET, all pinned with -R.
  pr_cell="n/a"; ci_cell="n/a"
  origin_slug=$(repo_slug "$dir") || origin_slug=""
  slug=""
  if [ "$GH_OK" = yes ] && [ -n "$origin_slug" ]; then
    slug=$(canonical_slug "$origin_slug")
    if [ -z "$slug" ]; then
      note "$S_CI" "$name" "origin '$origin_slug' is not reachable on GitHub (renamed away, deleted, or no access) -- PR, sync-block and CI checks skipped for this repo"
      pr_cell="?"; ci_cell="unreachable"
    elif [ "$slug" != "$origin_slug" ]; then
      note "$S_CI" "$name" "origin says '$origin_slug' but GitHub redirects it to '$slug' -- that repo was renamed. This directory shares one GitHub repo with every other clone of '$slug', so the PRS/CI columns below are '$slug''s, not this directory's alone."
    fi
  fi
  if [ -n "$slug" ]; then
    gh_load "$slug"
    key=$(printf '%s' "$slug" | tr '/' '_')
    # Several directories can resolve to ONE GitHub repo (rename redirects). Emit its
    # PR/CI findings once, labelled with the canonical repo, so one broken run does not
    # print three times and bury something else. Cells are still filled per directory.
    gh_label=${slug#*/}
    if [ -f "$CACHE/emitted_$key" ]; then emit=no; else emit=yes; : >"$CACHE/emitted_$key"; fi

    npr=$(grep -c . "$CACHE/pr_$key" 2>/dev/null | tr -d ' '); [ -z "$npr" ] && npr=0
    nsync=0
    while IFS=$'\t' read -r num head title; do
      [ -n "$num" ] || continue
      case "$head" in
        sync/upstream-*)
          nsync=$((nsync + 1))
          [ "$emit" = yes ] && note "$S_SYNCBLOCK" "$gh_label" "open sync PR #$num ($head) BLOCKS ALL FUTURE SYNCS in this repo -- the sync workflow's OPEN_SYNC guard skips every run while it is open. This is a silent stoppage, not just an open PR. Resolve with the sync-resolve skill."
          ;;
        *) [ "$emit" = yes ] && note "$S_CI" "$gh_label" "open PR #$num ($head): $(trunc "$title" 60)" ;;
      esac
    done <"$CACHE/pr_$key"
    if [ "$nsync" -gt 0 ]; then pr_cell="${npr}!SYNC"; elif [ "$npr" -gt 0 ]; then pr_cell="$npr"; else pr_cell="0"; fi

    # latest run per workflow
    bad=""; nbad=0; nrun=0
    while IFS=$'\t' read -r wfname concl status url; do
      [ -n "$wfname" ] || continue
      nrun=$((nrun + 1))
      if [ "$status" != "completed" ]; then continue; fi
      case "$concl" in
        success|skipped) ;;
        *)
          nbad=$((nbad + 1))
          [ "$nbad" -le 2 ] && bad="${bad:+$bad,}$(trunc "$wfname" 10):$concl"
          [ "$emit" = yes ] && note "$S_CI" "$gh_label" "latest '$wfname' run is $concl -- an expired PAT, a revoked token or a broken shared workflow looks exactly like this and announces itself no other way. $url"
          ;;
      esac
    done <"$CACHE/run_$key"

    # auto-disabled + never-run workflows
    ndis=0
    while IFS=$'\t' read -r state wfname wfpath; do
      [ -n "$wfname" ] || continue
      if [ "$state" != "active" ]; then
        ndis=$((ndis + 1))
        [ "$emit" = yes ] && note "$S_CI" "$gh_label" "workflow '$wfname' is $state -- GitHub auto-disables scheduled workflows after ~60 days of repo inactivity, which silently stops syncing on a quiet tool. Re-enable it from the repo's Actions tab."
        continue
      fi
      if ! cut -f1 "$CACHE/run_$key" | grep -qxF "$wfname"; then
        is_scheduled "$dir/$wfpath" || continue   # tag-only / reusable-only: not a finding
        [ "$emit" = yes ] && note "$S_CI" "$gh_label" "scheduled workflow '$wfname' ($wfpath) has never run -- a schedule with no runs is a stoppage that looks like silence"
      fi
    done <"$CACHE/wf_$key"

    if [ "$nbad" -gt 0 ]; then
      ci_cell="$bad"
      [ "$nbad" -gt 2 ] && ci_cell="$ci_cell +$((nbad - 2))"
    elif [ "$ndis" -gt 0 ]; then
      ci_cell="${ndis} off"
    elif [ "$nrun" -gt 0 ]; then
      ci_cell="ok"
    else
      ci_cell="no runs"
    fi
  fi

  # 8. serverPackage. Anchored so a commented-out alternate is skipped; [^"]* so a
  #    trailing quoted comment cannot be swallowed into the value.
  toml="$dir/tool/lighttool.toml"
  if [ -f "$toml" ]; then
    wt=$(sed -n 's/^serverPackage *= *"\([^"]*\)".*/\1/p' "$toml" | head -1)
    hd=$(git -C "$dir" show HEAD:tool/lighttool.toml 2>/dev/null | sed -n 's/^serverPackage *= *"\([^"]*\)".*/\1/p' | head -1)
    if [ -n "$wt" ] && [ -n "$hd" ] && [ "$wt" != "$hd" ]; then
      note "$S_TOML" "$name" "serverPackage is '$wt' in the working tree but '$hd' at HEAD -- modified locally (legitimate for AVD work). Restore with: git -C $dir checkout -- tool/lighttool.toml"
    elif [ -n "$wt" ] && [ "$wt" != "$EXPECTED_PKG" ]; then
      # The SDK fork tracks upstream's value by design -- informational there, drift
      # anywhere else. Keyed on origin's own URL, not the canonical name, so a repo
      # rename cannot silently exempt a directory that genuinely drifted.
      case "$origin_slug" in
        */light-sdk) ;;
        *) note "$S_TOML" "$name" "committed serverPackage is '$wt', expected '$EXPECTED_PKG' -- this is how the repos once drifted apart" ;;
      esac
    fi
  fi

  # 9. Gitignored-but-precious local state: invisible to git status by design, lives
  #    in exactly one place, and is what a "clean tree, safe to delete" reading gets
  #    wrong. Presence only -- never contents.
  ls_found=""
  for p in .superpowers .remember local.properties sdk/emulator/keys; do
    [ -e "$dir/$p" ] && ls_found="${ls_found:+$ls_found }$p"
  done
  [ -n "$ls_found" ] && printf '%s\t%s\n' "$name" "$ls_found" >>"$LOCALSTATE"

  # shellcheck disable=SC2059
  printf "$ROW_FMT" "$(trunc "$name" 21)" "$(trunc "$branch" 24)" "$tree_cell" "$unpushed_cell" \
    "$behind_cell" "$up_cell" "$pr_cell" "$ci_cell"
done

echo
echo "BEHIND = commits the checked-out branch is behind its own origin. UPSTREAM = behind"
echo "upstream/main @ age of last fetch (a stale fetch means a stale number, not a safe one)."

# --- needs attention -----------------------------------------------------------
echo
if [ -s "$FINDINGS" ]; then
  echo "NEEDS ATTENTION (most severe first)"
  echo "=================================="
  label=""
  sort -s -t"$(printf '\t')" -k1,1n "$FINDINGS" | while IFS=$'\t' read -r sev repo msg; do
    case "$sev" in
      "$S_UNPUSHED") l="1. UNPUSHED -- exists nowhere else" ;;
      "$S_AHEAD")    l="2. UNPUSHED -- ahead of its own remote" ;;
      "$S_SYNCBLOCK")l="3. BLOCKED SYNC" ;;
      "$S_CI")       l="4. CI / PRs" ;;
      "$S_DRIFT")    l="5. UPSTREAM DRIFT" ;;
      "$S_TOML")     l="6. serverPackage" ;;
      *)             l="7. LOCAL STATE" ;;
    esac
    if [ "$l" != "$label" ]; then printf '\n%s\n' "$l"; label=$l; fi
    printf '  [%-20s] %s\n' "$(trunc "$repo" 20)" "$msg"
  done
else
  echo "NEEDS ATTENTION: none. All clear."
fi

# --- footers -------------------------------------------------------------------
if [ -s "$LOCALSTATE" ]; then
  echo
  echo "LOCAL-ONLY STATE (gitignored, invisible to git status, exists in one place only)"
  while IFS=$'\t' read -r repo paths; do printf '  %-21s %s\n' "$repo" "$paths"; done <"$LOCALSTATE"
fi

if [ "$GH_OK" != yes ]; then
  echo
  echo "NOTE: $GH_WHY -- PR, sync-block and CI checks were SKIPPED (shown as n/a)."
  echo "      Those are the checks nothing local can substitute for. Fix gh and re-run."
fi

echo
echo "Scanned $REPO_COUNT git repo(s) under $WORKSPACE. Token expiry is not inspectable"
echo "locally (Actions secrets) -- a red scheduled run is the proxy. lightphone/* is read-only."
