# Upstream backlog — private SDK patches, dropped and documented

**Written 2026-07-26.** Two real SDK bugs were found and fixed locally during tool development, then **deliberately dropped** so the tool repos sync with `lightphone/light-sdk` without recurring conflicts. Nothing was filed upstream. This document is the record: what each bug is, the exact patch, the evidence it worked, and how to recover or file it later.

## Why they were dropped rather than carried

Light's build server extracts only `tool/lighttool.toml`, `tool/build.gradle.kts`, `tool/src/main/kotlin/**`, and resources/assets from a submitted commit, then compiles against **their** pinned official SDK. A patch under `sdk/` or `plugin/` is therefore **never present in a build Light signs** — carrying one privately means the local build behaves differently from the published one, silently.

Worse, both patches lived in files upstream actively edits, so every SDK release re-collided with them. That was the direct cause of the repeated "manual resolution needed" sync PRs in light-sudoku and light-ledger.

So the calculus is: a private SDK patch buys local-only correctness, costs a permanent merge-conflict tax, and cannot ship. Dropping them makes syncs clean. The bugs remain real and unfixed — for anyone, including Light's own tools.

## Recovering a dropped patch

Every patch below is a permanent ancestor of its repo's `main`, so nothing is lost:

```bash
git -C ~/Documents/lightphone/light-sudoku show 3647845      # read it
git -C ~/Documents/lightphone/light-sudoku cherry-pick 3647845   # re-apply it
```

Before re-applying or filing, **check whether upstream has since fixed it** — these are pre-1.0 files under active change:

```bash
git fetch upstream main
git show upstream/main:sdk/client/src/main/kotlin/com/thelightphone/sdk/LightActivity.kt | grep -n 'safeDrawing\|handleOnBackPressed' -A4
```

---

## Candidate 1 — Edge-to-edge content is clipped by the LP3's camera cutout

**Severity:** cosmetic-to-broken depending on layout. Affects every tool, including Light's own weather and authenticator.

**Symptom.** Content drawn flush to the top of the window is clipped underneath the Light Phone III's camera punch-hole. Observed concretely in Sudoku: a top-docked floating keypad lost its entire header row on hardware.

**Why it hides.** The emulator defines no cutout geometry, so the same layout renders correctly there. This is only visible on a real device — which is why it survived into shipped SDK versions.

**Root cause.** `LightActivity` renders edge-to-edge and hides the system bars, but never applied compensating `WindowInsets` padding anywhere. There is exactly one root `Column` that every screen renders through, and it had no inset handling.

**The patch** (`light-sudoku` commit `3647845`, `sdk/client/src/main/kotlin/com/thelightphone/sdk/LightActivity.kt`, +2/−1):

```diff
+import androidx.compose.foundation.layout.safeDrawingPadding
@@
-                Column(modifier = Modifier.fillMaxSize()) {
+                Column(modifier = Modifier.fillMaxSize().safeDrawingPadding()) {
```

`safeDrawing` is the union of system bars, IME, and display cutout. It was chosen over `displayCutout` alone for defensive headroom against a transient system-bar swipe-reveal; the other two components are inert today (bars are explicitly hidden, and no SDK screen can summon the IME), so in practice it reduces to the cutout fix.

**Verification evidence (already done, worth citing if filed).** Enabled the emulator's real punch-hole cutout RRO and confirmed via `dumpsys window displays` that WindowManager reported a genuine top inset; the keypad header then rendered with clear margin below the cutout. A zero-regression pass with the cutout disabled showed pixel-identical rendering to before.

**Known open question, never verified on hardware.** Light-themed screens may show a black band (the window background) in the cutout strip rather than the theme's own background color, because the padding only affects the content area. Probably acceptable — it matches standard Android cutout letterboxing — but untested. Any upstream filing should say so plainly rather than claim a clean fix.

**Dropped in:** `light-sudoku` PR #5 (merge `fcfe434`, resolution commit `ed2ad47`) took upstream's `LightActivity.kt` wholesale.

---

## Candidate 2 — System back bypasses `LightViewModel.onBackPressed()`

**Severity:** the stronger of the two. This is an internal inconsistency in upstream's own API, not an oversight in a corner case.

**Symptom.** The system back key hard-pops the current screen, discarding in-progress state, while the on-screen back button correctly unwinds it. Two independent instances:

- **Sudoku:** one system back from the game screen with the hint sub-page open jumped straight to Home, instead of unwinding hint → menu → closed.
- **Ledger:** system back on a multi-step screen (AddEntry's category grid → amount entry) popped the whole screen outright, dropping in-progress input.

**Root cause.** The SDK ships `LightViewModel.onBackPressed()` as a "handled" hook, and `LightScreen.goBack()` consults it — but only on the in-app path. `LightActivity`'s `OnBackPressedCallback` calls the activity's own unconditional `goBack()` pop, so the hook is silently ignored for the hardware/system back key. **The hook upstream designed is honored on one of the two paths that should honor it.** Any tool with nested or overlay state loses state on system back, and there is no way to fix it from `tool/` — the callback lives in `sdk/client`.

**Two variants were written.** Both target the same line in `LightActivity.handleOnBackPressed()`.

*Ledger's variant* (commit `c1e9764`, direct call — simpler, no SDK API addition):

```diff
                 override fun handleOnBackPressed() {
-                    goBack()
+                    val screen = currentScreen.value?.screen
+                    if (screen != null) {
+                        screen.goBack()
+                    } else {
+                        goBack()
+                    }
                 }
```

*Sudoku's variant* (commit `9f5f8d1`, +6/−1 in `LightActivity.kt` plus +9 in `LightScreen.kt`) routed through a new non-generic helper, because `LightActivity` holds the screen star-projected:

```kotlin
// added to SimpleLightScreen in sdk/client/.../LightScreen.kt
/**
 * System back lands here so [goBack] overrides can intercept it — e.g.
 * [LightScreen] consults its view model's onBackPressed() before popping.
 * Non-generic so [LightActivity] can call it on a star-projected screen.
 */
internal fun requestBack() {
    goBack(null)
}
```

Ledger's direct `screen.goBack()` compiled without the helper, so **prefer ledger's variant** if re-applying or proposing — it's a strictly smaller change with no API surface added. Screens whose view model returns the default `onBackPressed() = false` pop exactly as before under either variant, and the empty-stack `finish()` path is untouched.

**Verification evidence.** Sudoku, on the Light_Phone AVD: hint sub-page → back → menu → back → game → back → Home, with progress persisting throughout; Home/Archive pop behavior unchanged.

**Dropped in:** `light-sudoku` — the `LightActivity` half went with PR #5, leaving `requestBack()` orphaned with zero call sites; the helper was then removed in `0be9dbf` (PR #6). `light-ledger` — dropped in the `chore/drop-backnav-patch` PR, 2026-07-26.

**If filed upstream, this is the better first issue.** It needs no design argument: their own hook is being skipped, the fix is a handful of lines, it's reproducible on the emulator (unlike Candidate 1), and it affects every tool with nested state.

---

## Private deltas that were NOT dropped

These remain as deliberate local deltas. Each will conflict whenever upstream touches the same file, and none of them ship through Light's builder.

| Repo | Path | What it does | Why kept |
|---|---|---|---|
| light-ledger | `sdk/client/.../LightDb.kt` (`b678249`) | Adds a `destructiveMigration: Boolean = false` parameter to `buildDatabase`, applying `fallbackToDestructiveMigration(dropAllTables = true)` | **Load-bearing.** Three tool call sites pass `destructiveMigration = true` (`ui/home/HomeScreen.kt:54`, `simplefin/LedgerJobs.kt:83`). Dropping it breaks compilation. |
| light-ledger | `plugin/.../LightSdkPlugin.kt` + its validation test (`fad0f8e`) | `isUnitTestConfig` — exempts unit-test configurations from the dependency-substitution guard | **Load-bearing.** The tool's `testImplementation(robolectric, androidx-test-core, kotlinx-coroutines-test)` are not on `ALLOWED_DEPENDENCIES`, so Robolectric DAO tests won't build without it. |
| light-sudoku, light-ledger | `lint-rules/build.gradle.kts` | Replaces `rootProject.ext["lintVersion"]` with a hardcoded pin (sudoku: `31.13.2`) | Kept to avoid scope creep during the sync. **Latent risk:** a hardcoded lint-api version diverging from the root project's can surface as `NoSuchMethodError` at lint time. Worth revisiting. |
| all five | `.github/workflows/*`, `gradle/gradle-daemon-jvm.properties`, `settings.gradle.kts`, AGP bump | Fork-local CI wiring and toolchain config | Intentional and permanent — these are what make the repos ours rather than SDK clones. |

**The `LightDb.kt` one deserves a decision eventually.** It's a public API change, and upstream's CONTRIBUTING explicitly says they are *not* interested in public API changes — so it is a poor upstream candidate as written. The alternatives are to keep carrying it, or to remove the need for it in ledger by shipping a real Room 1→2 migration instead of destructive fallback (see the note at `tool/.../data/LedgerDatabase.kt:15`).

---

## If and when you do file upstream

The process is not optional and PRs that skip it get closed:

1. **Issue first.** `lightphone/light-sdk` closes any PR not tied to an existing issue where a maintainer has explicitly green-lit the work. Bug reports and allow-list additions are welcome categories; public API changes and architectural changes are explicitly not.
2. **Wait for the green light** before opening the PR. The fork `tyleryancey/light-sdk` exists for exactly this — its `main` mirrors upstream, and work goes on a `fix/*` branch.
3. **Write it yourself.** Their AI/LLM policy requires that all communication come from a human, that you can explain the change in your own words, and that you are responsible for anything from your account. Preparing a patch locally is fine; the prose must be yours.
4. **Useful precedent.** Community bug reports and UI-library fixes get fast, warm maintainer responses, and there's a merged precedent for dependency allow-list requests (issue #40 → PR #44). For capability requests the maintainer's stated pattern is "file an issue, tag me, and reference this discussion."
5. **Both candidates above are already written up with reproduction and verification** — the technical work is done; only the human-authored filing is missing.
