---
name: run-light-tool
description: Build, install, launch, and drive this repo's LightOS tool on a connected AVD emulator or a physical Light Phone 3 over adb. Use whenever asked to run, start, launch, build, install, or reinstall the tool, screenshot it, tap or type into its UI, check whether a change actually works on the device (not just in tests), reproduce a UI bug, or QA before a release or submission. Works unchanged in any of the five Light Phone tool repos (light-chess, light-ledger, light-ringtone-studio, light-sudoku, light-tides) — it reads the package name from tool/lighttool.toml at runtime.
---

These are Android apps for LightOS (Light Phone 3), built with the SDK's Gradle plugin and driven entirely through `adb`. There is no web or desktop equivalent and no dev server — "running it" always means installing onto an AVD or a physical LP3 and driving it with taps and screenshots.

Use the driver script for that. It wraps `adb`/`gradlew` for build, install, launch, tap/type input, screenshots, and on-device file listing. It is repo-agnostic: it finds the repo root by walking up from your **current working directory** and reads the package name from `tool/lighttool.toml`'s `id`, so the same script drives any of the five tool repos with no edits.

```bash
D=~/.claude/skills/run-light-tool/scripts/driver.sh      # user-level install (the normal case)
D=.claude/skills/run-light-tool/scripts/driver.sh        # only if vendored into the repo
```

Every example below uses `$D`. **Run them from inside the tool repo you're working on** — the driver locates the repo from your cwd, so from `/tmp` or another repo it will fail loudly (by design) rather than drive the wrong tool. All other paths (`tool/lighttool.toml`, `./gradlew`) are relative to the repo root, where `gradlew` and `settings.gradle.kts` live.

## Prerequisites

- macOS with Android Studio's SDK installed; `adb` on `PATH` (`~/Library/Android/sdk/platform-tools`).
- **GitHub Packages credentials for Gradle**, or the build fails immediately with a 401 / package-resolution error before compiling anything: env vars `GH_PACKAGES_USER` / `GH_PACKAGES_TOKEN`, or `gpr.user` / `gpr.key` in `local.properties`. The SDK README's property names are wrong — `settings.gradle.kts` is the authority. This exact confusion has cost real debugging time; check it first when `./gradlew` dies instantly.
- A connected target: a running AVD (`~/Library/Android/sdk/emulator/emulator -avd <name>`) and/or a physical LP3 over USB with debugging enabled.

## Pin a device first

```bash
adb devices -l
export ANDROID_SERIAL=<serial>        # e.g. emulator-5554, or LP3LHMA531900321 for a real LP3
adb shell getprop ro.product.model    # guard: confirm it's the device you think it is
```

Do this before anything else. **Multiple attached devices is the default state here, not an edge case** — an AVD and a physical LP3 are often both connected. Every `adb` and `gradlew` call needs `ANDROID_SERIAL` pinned, or it either errors on ambiguity or silently targets the wrong device, which looks like "my change didn't take effect." The driver refuses to run without it.

## Check serverPackage against your target — before building

`tool/lighttool.toml` commits `serverPackage = "com.lightos"`, which targets real hardware.

| target | what to do |
|---|---|
| Physical LP3 | Nothing. The committed value is already correct — build and install directly. |
| AVD | Temporarily set `serverPackage = "com.thelightphone.sdk.emulator"`, build, then restore with `git checkout -- tool/lighttool.toml` when you're done. |

**A mismatch produces no error at all.** The tool simply binds to a server package that isn't present, so the failure surfaces as a stuck loading screen or dead UI rather than anything naming the real cause. That silence is why this deserves an explicit check before every build, not just when something looks wrong. `$D build` prints the target model alongside the committed `serverPackage` and warns on an apparent mismatch — advisory only; it never edits the file.

Make the AVD edit by hand and leave it visible. There used to be a `flip` command that made it for you; **it was removed deliberately and should not be re-added or re-scripted.** Its only purpose was to make an edit that must never be committed, and it hid that edit from `git status` — which is how five repos drifted into inconsistent committed values. A modified `tool/lighttool.toml` in `git status` *is* the reminder to restore it. CI is the backstop: submission-check runs on every pull request and fails if the committed value isn't `com.lightos`, because Light's builder compiles the committed value — an emulator `serverPackage` yields an APK that cannot bind to LightOS on real hardware.

## Build, launch, drive

```bash
$D build
$D launch
$D screenshot /tmp/home.png     # then actually look at it
```

| command | what it does |
|---|---|
| `build` | `gradlew :tool:installDebug` on `$ANDROID_SERIAL`, after printing target/`serverPackage` |
| `launch` | `am start` the tool, then waits out the SDK's loading interstitial (see Gotchas) |
| `killstart` | hard `am force-stop` + relaunch — the real persistence test, not just backgrounding |
| `screenshot <path>` | `adb exec-out screencap -p > path` |
| `tap <x> <y>` | `adb shell input tap` |
| `type <text>` | `adb shell input text`, safely quoted for the remote shell (see Gotchas) |
| `files [subdir]` | lists the tool's private `files/` dir (or a subdir, e.g. `files shared/ringtones`) via `run-as` |
| `uninstall` | `adb uninstall` the tool |

## Coordinates

Both the AVD and the physical LP3 render at an identical **1080×1240**, so tap coordinates are stable across targets — calibrate on the emulator and the same numbers work on hardware.

The SDK's own chrome sits at fixed positions across every tool, since it comes from `LightTopBar`/`LightBottomBar` rather than tool code:

- top-bar back label (top-left): roughly `100 60`
- bottom-bar primary action: roughly `540 1160`

Treat both as **starting points to verify with a screenshot, not guarantees.** A top bar with a trailing icon, or a bottom bar with two actions, puts things elsewhere. Derive everything tool-specific from a screenshot rather than guessing, and screenshot after each tap while you're still learning a screen — that is how you notice a tap landed on the wrong control, or navigated somewhere unexpected, instead of debugging a phantom bug later.

## Worked example

```bash
$D launch
$D screenshot /tmp/1-home.png      # confirm you're on the tool, not the interstitial
$D tap 540 1160                    # bottom-bar primary action
$D screenshot /tmp/2-next.png
$D type "O'Brien & Co"             # quoting is handled — see Gotchas
$D tap 540 1160                    # may kick off an async save/render
sleep 2                            # let the write land before checking
$D files                           # what's actually on disk
$D screenshot /tmp/3-result.png    # success vs. error state
$D killstart                       # did it persist across a hard kill?
$D screenshot /tmp/4-restart.png
```

## Test without a device

```bash
./gradlew :tool:test           # pure-JVM logic tests, no device needed
./gradlew :tool:assembleDebug  # compiles against the full SDK — catches API drift that installDebug's UP-TO-DATE cache can hide
```

## Gotchas

- **`am start` returns before the UI is ready.** For ~3s after launch, LightActivity shows a generic SDK "loading…" interstitial while it connects to the LightService/RPC, before the tool's own screen renders. A screenshot taken immediately shows the interstitial, not your tool — and a tap sent then goes nowhere. `launch`/`killstart` already sleep 4s to cover this: don't shorten it, and don't skip it if you bypass the driver and call `adb shell am start` yourself.
- **`adb shell` re-parses its argument on the device's own shell, so local quoting alone doesn't protect anything.** `adb shell` joins its argv into one string and the device shell re-splits it. That's why `type` routes text through the driver's `remote_quote()`: without it, names containing spaces, apostrophes (`O'Brien`), `&`, or `$` silently truncate, expand, or abort on-device. If you call `adb shell input text ...` directly, quote for the remote shell yourself.
- **Async writes race your checks.** After any action that kicks off a save, render, or file write, wait ~2s before listing files or screenshotting. Checking immediately shows pre-write state — an empty directory or a stale screen — which reads exactly like a bug that isn't there.
- **Light-gated SDK APIs return `NoPermission` on real, non-vetted hardware. This is expected, not a bug.** Production LightOS defaults to `ClientFilterLevel.AllowLightApprovedApks`, which requires a Light-signed certificate, and there is **no on-device or adb-reachable override on real hardware** — it needs Light's actual Tool Library vetting. Don't go hunting for a toggle or debug flag; there isn't one. Everything up to that call still works and is worth verifying on device.
- **On a fresh AVD only, the equivalent gate *is* locally bypassable:** Settings → Allowed Tools → "All Tools". One-time per AVD. This is emulator-only debug tooling that does not exist in production, so a gated call succeeding on the AVD tells you nothing about real hardware.
- **`run-as` (what `files` uses) needs a debuggable build.** `installDebug` gives you one. It won't work against a release APK.
