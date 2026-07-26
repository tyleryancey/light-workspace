# Aftercare checklist (each item is a user decision)

- [ ] Delete old local folders `light-tools/` and `light-tools-tides/` (everything is pushed; ~1.4 GB back)
- [ ] Delete `light-tools-sun-and-moon/` (spec rescued to specs/sun-and-sky.md) and the four `Untitled_*` files (rescued to notes/)
- [ ] Delete `~/Documents/lightphone.zip` (755 MB) and `~/Documents/light-tools-tides.zip` (79 MB)
- [ ] Review then archive/delete `~/Documents/light-phone-3-lightos-dev/` (1.5 GB; contains an untracked ledger plan doc — check before deleting) and the `tyleryancey/light-sdk-sudoku-port` GitHub repo
- [ ] `./gradlew clean` in idle projects (~2.3 GB regenerable output)
- [ ] Review/merge the open sync PRs the smoke test created in each tool repo
- [ ] Write and file the safe-drawing-insets issue upstream (human-authored, issue-first; patch lives in light-sudoku's sdk/ delta)
- [ ] Post chess, ledger, ringtone-studio, tides in Discussions → Tools; PR all tools to garado/awesome-light
- [ ] Create `run-<tool>` Claude deploy skills in the other four repos, modeled on light-ringtone-studio's
- [ ] First release for chess (SUBMISSION.md exists; tag v1.0.0 when QA'd), ringtone-studio and ledger when ready
- [ ] Set LIGHT_PACKAGES_TOKEN and LIGHT_CI_PAT secrets on light-chess, light-ledger, light-ringtone-studio, light-tides (until then their `check` CI fails on packages auth AND the Monday 14:00 UTC sync cron fails on checkout — set before Mon 2026-07-28 to avoid red runs)
- [ ] Write a per-tool README for each of the five repos (they still show the SDK's README) before posting to Discussions/awesome-light
- [ ] Note: classic PATs expire — when LIGHT_CI_PAT/LIGHT_PACKAGES_TOKEN rotate, update secrets on all five repos; GitHub also auto-disables cron workflows after ~60 days of repo inactivity (re-enable via Actions tab)
