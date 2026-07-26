# LightOS emulator setup

Two levels of emulator exist, and picking the right one saves a lot of wasted setup.

**A plain AVD** runs your tool like any Android app. Enough for layout, navigation, and logic work — which is most day-to-day development.

**The LightOS emulator installed as a privileged system app** is the only way to exercise push notifications and special permissions off real hardware, because those need the LightService running with system privileges. It's a genuinely fiddly one-time-per-machine setup.

Upstream's canonical instructions are `docs/system_app/README.md` in `lightphone/light-sdk` (mirrored locally at `~/Documents/lightphone/light-sdk`). **Read that file rather than trusting this one blindly** — it's pre-1.0 and changes. This document captures the shape of the process, the values that matter, and the traps.

## Plain AVD — matching the LP3

Per upstream's README, an AVD that "generally feels like an LPIII":

| Setting | Value |
|---|---|
| Screen | 1080 × 1240, 3.92" |
| API | 34 (Android 14) |
| Google Play Services | **none** — use an AOSP/`default` target, not `google_apis_playstore` |
| Architecture | arm64-v8a (Apple Silicon) or x86_64 |

The 1080 × 1240 match matters more than it looks: a real LP3 renders at exactly the same resolution, so tap coordinates and screenshots transfer between AVD and device without adjustment.

**For any AVD work, `tool/lighttool.toml` must temporarily read `serverPackage = "com.thelightphone.sdk.emulator"`.** The committed value is `com.lightos` (it targets real hardware, and Light's builder compiles whatever is committed). Restore with `git checkout -- tool/lighttool.toml` when you're done — a mismatched `serverPackage` produces no error, the tool just binds to a server package that isn't there.

**One AVD-only escape hatch worth knowing:** Settings → Allowed Tools → "All Tools" lowers `ClientFilterLevel` from its default `AllowLightApprovedApks`, so an unsigned tool will run. One-time per AVD. This is emulator-only debug tooling — it does not exist in production LightOS, which is why Light-gated APIs return `NoPermission` on real non-vetted hardware no matter what you do locally.

## LightOS emulator as a system app

Only needed for push notifications and special permissions. Six stages; the ordering is load-bearing.

**1. Create the AVD** with the settings above — but with one extra hard requirement: the system image must be built with `test-keys`. Check with `adb shell getprop ro.build.description`; it must end in `test-keys`. Production/user-signed images reject the AOSP platform test key the emulator app is signed with, and the failure surfaces as mismatched signature hashes in `dumpsys`, which is not an obvious symptom.

**2. Boot with a writable system partition:** `emulator -avd <name> -writable-system`, then `adb root && adb remount`. The flag is required *every* boot, not just the first. If `remount` fails with a verity error: `adb disable-verity`, `adb reboot`, then `adb root && adb remount` again.

**3. Generate the platform signing key** into `sdk/emulator/keys/platform.jks`. The emulator app must be signed with the AOSP platform test key so it can share `uid 1000` with the system. Upstream's instructions download `platform.x509.pem` and `platform.pk8`, convert the pk8 to PEM with `openssl pkcs8`, bundle them into a PKCS#12, and import that into a Java keystore with `keytool`. These are the well-known AOSP **test** keys — not secret, and only usable against `test-keys` images. Copy the exact commands from upstream's doc rather than reconstructing them; the openssl/keytool invocations are easy to get subtly wrong.

**4. Build:** `./gradlew :sdk:emulator:assembleDebug`.

**5. Install as a privileged system app** — push the APK to `/system/priv-app/LightOSEmulator/LightOSEmulator.apk` (both the directory name and the file name matter) and `adb reboot` so PackageManager picks it up. Verify two things: `adb shell pm path com.thelightphone.sdk.emulator` shows the priv-app path, and `adb shell dumpsys package com.thelightphone.sdk.emulator | grep uid=` shows `uid=1000`. Anything other than 1000 means it installed as a normal app and the whole point is lost.

**6. Iterate without rebooting:** after the first successful install, `./gradlew :sdk:emulator:assembleDebug && adb install -r sdk/emulator/build/outputs/apk/debug/emulator-debug.apk` retains the system uid as long as the signing key and `sharedUserId` are unchanged. The emulator app logs a warning on startup if it isn't running as a system app — worth watching for.

**Two optional touches that make it feel like a real LP3:** set the emulator as the Android launcher (`adb shell cmd package set-home-activity com.thelightphone.sdk.emulator/.MainActivity`), and zero the three animation scales (`window_animation_scale`, `transition_animation_scale`, `animator_duration_scale`), since LightOS uses no cross-tool animations.

Upstream's own troubleshooting table covers the common failures — wrong uid, verity/bootloader complaints, app missing after reboot, signature mismatch. Consult it rather than improvising.

## Prerequisites that bite before you start

Gradle can't resolve the SDK's dependencies without GitHub Packages credentials, and the failure is an immediate 401 that looks unrelated to setup. Provide `GH_PACKAGES_USER` / `GH_PACKAGES_TOKEN` as environment variables, or `gpr.user` / `gpr.key` in `local.properties`. **The SDK README's property names are wrong** — this has cost real debugging time more than once.

`adb` and `emulator` come from the Android SDK install (`~/Library/Android/sdk/platform-tools` and `.../emulator` on macOS); add them to `PATH`.

## Why this may all be temporary

Upstream has said the current shape of this is transitional. Their July 2026 priorities post states they're building a way to install local builds over the local network via LightOS, alongside a File Manager, explicitly so that adb is *not* a requirement for tool development. They've also said there's no officially supported way to enable developer mode today, that third-party methods are tolerated ("the hardware is yours!"), and that they reserve the right to break those methods without notice — with dashboard-based installs estimated for late August 2026.

So treat this document as a snapshot. When something here stops working, check upstream's `docs/system_app` and their Discussions before debugging deeply — the ground may simply have moved.

## Related

- `docs/SYNCING.md` — resolving upstream SDK syncs
- `docs/UPSTREAM.md` — how to report SDK bugs you find during device testing
- The `run-light-tool` skill — build, install, launch, and drive a tool on either target
