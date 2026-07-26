#!/usr/bin/env bash
# Usage: ci/create-tool-repo.sh <tool> <source-branch> "<description>"
#
# Run from within a clone of tyleryancey/light-sdk (or any clone that has
# <source-branch> as a local branch) — light-sdk mirrors upstream on main only.
# For a brand-new tool: branch off main, set tool/lighttool.toml's identity
# (unique id, label, versionCode = 1, semver versionName,
# serverPackage = "com.lightos"), commit, then run this script with that
# branch name.
set -euo pipefail
TOOL="$1"; BRANCH="$2"; DESC="$3"
REPO="tyleryancey/light-$TOOL"
RAW="https://raw.githubusercontent.com/tyleryancey/light-workspace/main"

gh repo create "$REPO" --public --description "$DESC"
git push "https://github.com/$REPO.git" "refs/heads/$BRANCH:refs/heads/main"

TMP=$(mktemp -d)
git clone --quiet "https://github.com/$REPO.git" "$TMP/repo"
cd "$TMP/repo"

mkdir -p .github/workflows
for wf in check submission-check release sync; do
  curl -fsSL "$RAW/ci/callers/$wf.yml" -o ".github/workflows/$wf.yml"
done
curl -fsSL "$RAW/ci/templates/pull_request_template.md" -o .github/pull_request_template.md
rm -f .github/workflows/sync-upstream.yml .github/workflows/pr-check.yml

ID=$(sed -n 's/^id *= *"\([^"]*\)".*/\1/p' tool/lighttool.toml)
LABEL=$(sed -n 's/^label *= *"\([^"]*\)".*/\1/p' tool/lighttool.toml)
curl -fsSL "$RAW/ci/templates/README.md" \
  | sed -e "s|{{LABEL}}|$LABEL|g" -e "s|{{ID}}|$ID|g" -e "s|{{REPO}}|$REPO|g" \
  > README.md

if [ ! -f SUBMISSION.md ]; then
  VN=$(sed -n 's/^versionName *= *"\([^"]*\)".*/\1/p' tool/lighttool.toml)
  VC=$(sed -n 's/^versionCode *= *\([0-9]*\).*/\1/p' tool/lighttool.toml)
  PERMS=$(sed -n '/^permissions *=/s/.*\[\(.*\)\].*/\1/p' tool/lighttool.toml)
  curl -fsSL "$RAW/ci/templates/SUBMISSION.md" \
    | sed -e "s|{{LABEL}}|$LABEL|g" -e "s|{{ID}}|$ID|g" -e "s|{{REPO}}|$REPO|g" \
          -e "s|{{VERSION}}|$VN|g" -e "s|{{VERSIONCODE}}|$VC|g" -e "s|{{PERMISSIONS}}|${PERMS:-none}|g" \
    > SUBMISSION.md
fi

git add -A
git commit -m "ci: adopt reusable workflows from light-workspace"
git push origin main

gh repo edit "$REPO" --add-topic lightphone --add-topic lightos --add-topic light-phone-3

# Branch protection last (so the setup commit above could land directly on main):
gh api -X PUT "repos/$REPO/branches/main/protection" --input - <<'JSON'
{
  "required_status_checks": {"strict": false, "contexts": ["check / check", "submission-check / submission-check"]},
  "enforce_admins": false,
  "required_pull_request_reviews": {"required_approving_review_count": 0},
  "restrictions": null
}
JSON
echo "OK: https://github.com/$REPO"
