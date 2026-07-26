#!/usr/bin/env bash
# Local mirror of the release gates in light-workspace's reusable-release.yml and
# reusable-submission-check.yml. Run this BEFORE pushing a v* tag: a failure here
# costs one edit, while the same failure in CI costs a pushed tag that has to be
# deleted remotely AND locally before you can retry.
#
# Usage: preflight.sh [repo-dir]     # repo-dir defaults to the current directory
#
# Reads only. Fetches from origin (to make the tag and origin/main comparisons
# honest) and exits non-zero on the first hard failure.
set -u

REPO_DIR=${1:-.}
cd "$REPO_DIR" 2>/dev/null || { echo "preflight: cannot cd to '$REPO_DIR'"; exit 2; }

ok()   { printf '  [ok]    %-24s %s\n' "$1" "$2"; }
warn() { printf '  [warn]  %-24s %s\n' "$1" "$2"; }
fail() { printf '  [FAIL]  %-24s %s\n' "$1" "$2"; exit 1; }

TOML=tool/lighttool.toml

echo "release preflight — $(basename "$PWD")"

# --- repo shape -------------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || fail "git repo" "$PWD is not a git repo"
[ -f "$TOML" ]         || fail "repo layout" "no $TOML — run this from a light-<tool> clone (cwd=$PWD)"
[ -f SUBMISSION.md ]   || fail "repo layout" "SUBMISSION.md missing — reusable-release.yml greps it for the version"
ok "repo layout" "$PWD"

# --- refs -------------------------------------------------------------------
# Without a successful fetch, the tag and origin/main checks below can only warn:
# passing them off stale refs is the one false negative that lets a duplicate or
# unpushed-commit tag reach GitHub.
FETCHED=1
if git fetch --quiet --tags origin 2>/dev/null; then
  ok "fetch origin" "tags and branches refreshed"
else
  FETCHED=0
  warn "fetch origin" "fetch failed (offline? no origin?) — tag/origin checks below can only warn"
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || fail "branch" "actual=$BRANCH expected=main (releases are tagged on main)"
ok "branch" "actual=main expected=main"

DIRTY=$(git status --porcelain | tr '\n' ';')
[ -z "$DIRTY" ] || fail "clean tree" "uncommitted changes: $DIRTY(a leftover emulator serverPackage edit shows up here)"
ok "clean tree" "nothing uncommitted"

LOCAL=$(git rev-parse HEAD)
# -q --verify, not a bare rev-parse: on a missing ref a bare rev-parse echoes the
# literal string "origin/main" on stdout, which would sail past the -z test below.
REMOTE=$(git rev-parse -q --verify origin/main 2>/dev/null || true)
if [ -z "${REMOTE:-}" ]; then
  warn "up to date with origin" "no origin/main ref available locally"
elif [ "$LOCAL" = "$REMOTE" ]; then
  ok "up to date with origin" "HEAD == origin/main (${LOCAL:0:8})"
elif [ "$FETCHED" = 0 ]; then
  warn "up to date with origin" "HEAD ${LOCAL:0:8} != possibly-stale origin/main ${REMOTE:0:8}"
else
  AHEAD=$(git rev-list --count origin/main..HEAD)
  BEHIND=$(git rev-list --count HEAD..origin/main)
  fail "up to date with origin" "HEAD is $AHEAD ahead / $BEHIND behind origin/main — only tag what origin already has"
fi

# --- tool/lighttool.toml ----------------------------------------------------
# Anchored at line start so commented-out alternates are skipped, and [^"]* rather
# than .* so a trailing quoted comment on the same line cannot be captured. These
# are byte-for-byte the patterns both workflows use; do not "improve" them here or
# the skill starts lying about what CI will do.
VN=$(sed -n 's/^versionName *= *"\([^"]*\)".*/\1/p' "$TOML")
VC=$(sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p' "$TOML")
SP=$(sed -n 's/^serverPackage *= *"\([^"]*\)".*/\1/p' "$TOML")

[ -n "$VN" ] || fail "versionName present" "no ^versionName line in $TOML"
[ -n "$VC" ] || fail "versionCode present" "no ^versionCode line in $TOML"
[ "$(printf '%s\n' "$VN" | wc -l | tr -d ' ')" = "1" ] \
  && [ "$(printf '%s\n' "$VC" | wc -l | tr -d ' ')" = "1" ] \
  || warn "single definition" "more than one uncommented versionName/versionCode in $TOML — CI reads them the same ambiguous way"

printf '%s\n' "$VN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "versionName semver" "actual=$VN expected=x.y.z with no pre-release/build metadata (Light's builder rejects anything else)"
ok "versionName semver" "actual=$VN expected=x.y.z"

TAG="v$VN"

[ "$SP" = "com.lightos" ] \
  || fail "serverPackage" "actual=${SP:-<unset>} expected=com.lightos (an emulator value ships an APK that cannot bind to LightOS on real hardware)"
ok "serverPackage" "actual=com.lightos expected=com.lightos"

# --- the tag ----------------------------------------------------------------
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "tag $TAG is free" "tag already exists — a previous attempt got this far. Delete it first: git push origin :refs/tags/$TAG && git tag -d $TAG (or bump the version)"
elif [ "$FETCHED" = 0 ]; then
  warn "tag $TAG is free" "no local $TAG, but the fetch failed — a tag on origin would not be visible here"
else
  ok "tag $TAG is free" "not present locally or on origin"
fi

# --- versionCode strictly greater than the previous release's ---------------
# Same expression as reusable-release.yml: highest-SORTING v* tag other than this
# one, which is not necessarily the most recent one.
PREVTAG=$(git tag -l 'v*' --sort=-v:refname | grep -v "^${TAG}$" | head -1)
if [ -z "$PREVTAG" ]; then
  ok "versionCode increases" "actual=$VC — no prior v* tag, first release (CI skips this check too)"
else
  PREV_VC=$(git show "$PREVTAG:$TOML" 2>/dev/null | sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p')
  [ -n "$PREV_VC" ] || fail "versionCode increases" "could not read versionCode from $PREVTAG:$TOML"
  [ "$VC" -gt "$PREV_VC" ] \
    || fail "versionCode increases" "actual=$VC expected>$PREV_VC (previous release $PREVTAG) — bump versionCode alongside versionName"
  ok "versionCode increases" "actual=$VC expected>$PREV_VC (previous release $PREVTAG)"
fi

# --- SUBMISSION.md ----------------------------------------------------------
grep -q "$VN" SUBMISSION.md \
  || fail "SUBMISSION.md mentions" "$VN not found in SUBMISSION.md — update it before releasing"
ok "SUBMISSION.md mentions" "$VN matched (regex-loose, as in CI: dots match any char — eyeball the file)"

echo
echo "preflight passed for $TAG (versionCode $VC)."
echo "These are the CI-mirrorable checks only. Device QA on the physical Light Phone III"
echo "is not verifiable here — confirm it happened before you push the tag."
