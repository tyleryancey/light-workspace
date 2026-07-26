# Aftercare checklist (each item is a user decision)

- [ ] Delete old local folders `light-tools/` and `light-tools-tides/` (everything is pushed; ~1.4 GB back)
- [ ] Delete `light-tools-sun-and-moon/` (spec rescued to specs/sun-and-sky.md) and the four `Untitled_*` files (rescued to notes/)
- [ ] Delete `~/Documents/lightphone.zip` (755 MB) and `~/Documents/light-tools-tides.zip` (79 MB)
- [ ] Review then archive/delete `~/Documents/light-phone-3-lightos-dev/` (1.5 GB; contains an untracked ledger plan doc — check before deleting) and the `tyleryancey/light-sdk-sudoku-port` GitHub repo
- [ ] `./gradlew clean` in idle projects (~2.3 GB regenerable output)
- [ ] Review/merge the open sync PRs the smoke test created in each tool repo
- [ ] Optional, no longer urgent: file either upstream bug from `docs/UPSTREAM-BACKLOG.md` (human-authored, issue-first). Both private SDK patches were dropped 2026-07-26 so the repos sync cleanly; the bugs are documented with patches, evidence, and recovery instructions. The system-back one is the better first filing.
- [ ] Post chess, ledger, ringtone-studio, tides in Discussions → Tools; PR all tools to garado/awesome-light
- [x] Deploy skill for every repo — superseded 2026-07-26 by the generic `run-light-tool` skill (`skills/run-light-tool/`, installed at user level), which reads the package id from `tool/lighttool.toml` and works in any tool repo. Decide separately whether to keep `light-ringtone-studio/.claude/skills/run-ringtone-studio/` for its tool-specific commands (`ringtone-uri`, `audio-log`, its tap map) or retire it now that the generic driver covers the shared surface.
- [ ] Run `skills/install-skills.sh` after pulling on any new machine — it symlinks `skills/*` into `~/.claude/skills`
- [ ] First release for chess (SUBMISSION.md exists; tag v1.0.0 when QA'd), ringtone-studio and ledger when ready
- [x] Set LIGHT_PACKAGES_TOKEN and LIGHT_CI_PAT secrets on light-chess, light-ledger, light-ringtone-studio, light-tides — done 2026-07-25; all five repos now hold both secrets
- [ ] Write a per-tool README for each of the five repos (they still show the SDK's README) before posting to Discussions/awesome-light — sections and rationale in `docs/README-CHECKLIST.md`, skeleton in `ci/templates/README.md`
- [x] Normalize the committed `serverPackage` to `com.lightos` on all five repos — done 2026-07-26. Upstream commits `com.lightos` in every shipped example (weather, authenticator, ui-demo, audio-demo) and only the blank `tool/` scaffold commits the emulator value; Light's builder compiles the committed value, so an emulator `serverPackage` yields an APK that cannot bind to LightOS on real hardware. The emulator value is now a temporary local edit for AVD work only, restored with `git checkout -- tool/lighttool.toml`. Enforced going forward by the `serverPackage` gate in `reusable-submission-check.yml`, which fails any PR to `main` carrying the emulator value.
- [ ] Note: classic PATs expire — when LIGHT_CI_PAT/LIGHT_PACKAGES_TOKEN rotate, update secrets on all five repos; GitHub also auto-disables cron workflows after ~60 days of repo inactivity (re-enable via Actions tab)
