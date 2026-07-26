#!/usr/bin/env bash
# Install this repo's skills at user level by symlinking them into ~/.claude/skills.
#
# Symlinks rather than copies: the files stay version-controlled and reviewable
# here in light-workspace, and editing one takes effect immediately with no
# re-install step. Claude Code's skill discovery follows symlinks (verified), so
# a linked skill is indistinguishable from a copied one at use time.
#
# User level rather than per-repo: these skills are shared across all five tool
# repos, and copying them into each would recreate the five-copies drift the
# whole workspace layout exists to prevent. workspace-health additionally has to
# run from anywhere, since it spans repos.
#
# Usage: skills/install-skills.sh [--dry-run]
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.claude/skills"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY=1

mkdir -p "$DST"

for dir in "$SRC"/*/; do
  name=$(basename "$dir")
  case "$name" in _*) continue ;; esac   # skip scratch dirs like _symlink-test
  [ -f "$dir/SKILL.md" ] || { echo "skip $name (no SKILL.md)"; continue; }

  link="$DST/$name"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    # A real directory here would be shadowed silently by nothing — refuse
    # rather than clobber something the user installed by other means.
    echo "REFUSING $name: $link exists and is not a symlink" >&2
    continue
  fi

  current=$(readlink "$link" 2>/dev/null || true)
  if [ "$current" = "${dir%/}" ]; then
    echo "ok      $name (already linked)"
    continue
  fi

  if [ -n "$DRY" ]; then
    echo "would link $name -> ${dir%/}"
  else
    ln -sfn "${dir%/}" "$link"
    echo "linked  $name -> ${dir%/}"
  fi
done

echo
echo "Installed skills:"
find -L "$DST" -maxdepth 2 -name SKILL.md 2>/dev/null | sed "s|$DST/||;s|/SKILL.md||" | sort | sed 's/^/  /'
echo
echo "New or renamed skills appear in a fresh Claude Code session; edits to an"
echo "already-linked skill's contents take effect the next time it is read."
