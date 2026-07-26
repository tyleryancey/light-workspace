# Contributing upstream to lightphone/light-sdk

A checklist, deliberately not a skill. Every step here is either a judgment call or a piece of writing that has to be yours — automating it would break the one rule upstream cares most about.

**The vehicle is `tyleryancey/light-sdk`** — the fork, whose `main` mirrors upstream and is never committed to directly. Work goes on a `fix/*` or `feat/*` branch. `lightphone/*` is otherwise read-only: no pushes, no direct commits.

## The hard rules, and why they exist

**Issue first, always.** Upstream closes any pull request not tied to an existing issue where a maintainer has explicitly green-lit the work. This isn't bureaucracy — the SDK underpins shipping Light Phone products, so they gate what enters it. A PR that arrives cold is work nobody asked for, and it gets closed however good it is.

**Wait for the green light before opening the PR.** "I filed an issue" is not the same as "they said yes." Their contributing guide reserves the right to politely refuse any proposed work, and says outright: if having your work merged matters to you, wait.

**Write everything yourself.** Their AI/LLM policy requires that all communication come from a human, that you be able to explain any proposed change in your own words, and that you are responsible for whatever comes from your account. There's a real precedent: a PR with an agent-branded branch name got a warm but pointed redirect to the guidelines. Claude can help you understand a bug, prepare a diff, or verify a fix locally — the issue text, the PR description, and every comment are yours to write.

**Delete generated commentary.** If a patch was drafted with assistance, strip the explanatory comments an LLM tends to leave behind. They ask for this specifically.

## What they want, and what they don't

Welcome:
- Bug reports (the highest-value thing you can offer)
- Requests to add an open-source third-party library or an Android API to the build plugin's allow-list — there's merged precedent for exactly this
- Requests to add a permission to the allow-list
- Security issues
- Material performance improvements

Not welcome:
- Public API changes
- New or updated third-party dependencies (as opposed to allow-listing an existing one)
- Meaningful architectural changes

That third category is worth internalizing before you invest effort. A fix that requires changing a public signature is likely to be refused no matter how correct it is — which is why, for example, the `LightDb.kt` `destructiveMigration` parameter recorded in `docs/UPSTREAM-BACKLOG.md` is a poor candidate as written and better solved inside our own tool.

## Before you file

**Check it's still a bug.** These files change fast. Fetch upstream and read the current version of whatever you're reporting against — a fix may already have landed.

```bash
git -C ~/Documents/lightphone/light-sdk fetch upstream main
git -C ~/Documents/lightphone/light-sdk log --oneline upstream/main -15
```

**Check nobody else filed it.** Search both open and closed issues, and the Discussions.

**Confirm it's in the SDK, not in your tool.** The distinction decides whether upstream is even the right venue: if the behavior lives under `sdk/`, `plugin/`, or `lint-rules/`, you cannot fix it for a published build, because Light's builder extracts only `tool/lighttool.toml`, `tool/build.gradle.kts`, `tool/src/main/kotlin/**`, and resources/assets, then compiles against their own pinned SDK. A private patch under `sdk/` works locally and silently vanishes from anything Light signs. That asymmetry is the whole reason upstreaming matters rather than being a nicety.

**Reproduce it on the emulator if you can.** A bug that reproduces without LP3 hardware is dramatically easier for a maintainer to act on. If it only shows on hardware, say so explicitly and explain why (the safe-drawing-insets bug in the backlog is a good example — the emulator defines no cutout geometry, so it can't show there at all).

## What a good issue contains

Ordered roughly by how much it helps:

1. **The symptom**, concretely — what you saw, on what target, in what tool.
2. **Reproduction**, minimal. Emulator steps if possible.
3. **Root cause**, if you found it — the file and the mechanism.
4. **Why it affects more than you.** If the code path is shared, say which other tools go through it. A bug in a single choke point every tool renders through is a different priority than a corner case.
5. **The proposed fix**, sketched. Smallest change that works; no API additions if avoidable.
6. **Your verification** — what you ran, what you observed, and what you did *not* verify. Honest gaps read as credibility, not weakness.
7. **Open questions.** If your fix has a known cosmetic side effect you haven't tested, say so in the issue rather than letting a reviewer find it.

Keep it human and short. Their maintainers respond fast, specifically, and warmly to bug reports that respect their time.

## Then

Once a maintainer green-lights it: branch on the fork, make the change, run `./gradlew check`, open the PR referencing the issue, and keep the description in your own voice. If the change is a capability or allow-list request, their stated pattern is to file an issue, tag the maintainer, and reference the relevant discussion.

## What's queued right now

`docs/UPSTREAM-BACKLOG.md` holds two fully-analyzed SDK bugs, both with patches written, verified, and then deliberately dropped so the tool repos sync cleanly. Neither has been filed. The system-back one — where the SDK's own `LightViewModel.onBackPressed()` hook is honored for in-app back buttons but silently bypassed by the hardware back key — is the better first filing: it needs no design argument, it reproduces on the emulator, the fix is a few lines, and it affects every tool with nested state, including Light's own.

## Related

- `docs/UPSTREAM-BACKLOG.md` — the two queued bugs, with diffs and recovery instructions
- `docs/SYNCING.md` — resolving upstream syncs, including which private patches are load-bearing
- `docs/EMULATOR.md` — the emulator setup you'll need to reproduce anything
