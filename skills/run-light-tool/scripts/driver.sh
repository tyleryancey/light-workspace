#!/bin/bash
# Driver for building, installing, and driving ANY Light Phone 3 tool via adb.
# Usage: driver.sh <command> [args...]
# Requires ANDROID_SERIAL set (see require_serial).
#
# Repo-agnostic by design: nothing here names a specific tool. The package name
# is read at runtime from tool/lighttool.toml's `id`, so the same script works
# unchanged in every light-* tool repo.
set -euo pipefail

# --- repo root discovery ---------------------------------------------------
# Locate the repo root by walking UP FROM THE CURRENT WORKING DIRECTORY, not
# from this script's own location. This skill is installed at user level
# (~/.claude/skills/run-light-tool -> a checkout elsewhere on disk), so
# `dirname "$0"` points into the skill's own repo, not the tool repo being
# driven — and with a symlinked install it may not even be under any tool repo.
# The cwd is the only reliable signal for "which tool am I working on".
REPO_ROOT=""
PKG=""
ACTIVITY=""

find_repo_root() {
  local d="$PWD"
  while :; do
    if [ -f "$d/settings.gradle.kts" ] || [ -f "$d/settings.gradle" ] || [ -f "$d/gradlew" ]; then
      REPO_ROOT="$d"
      return 0
    fi
    [ "$d" = "/" ] && return 1
    d="$(dirname "$d")"
  done
}

require_repo() {
  [ -n "$REPO_ROOT" ] && return 0
  find_repo_root && return 0
  echo "Not inside a Light tool repo: no settings.gradle.kts/gradlew found in $PWD or any parent." >&2
  echo "cd into the tool repo (the dir holding gradlew and tool/lighttool.toml) and retry." >&2
  exit 1
}

# toml_value <key> — first uncommented `key = "value"` in tool/lighttool.toml.
# The `^[[:space:]]*` anchor skips commented-out lines (e.g. the
# `# serverPackage = "com.thelightphone.sdk.emulator"` line every repo carries),
# and the value is taken as the first quoted run on the line, so aligned `=`
# and trailing comments (`id  = "dev.tyler.x"  # permanent once published`)
# both parse correctly. awk exits itself after the first hit — deliberately not
# `sed ... | head -1`, which can SIGPIPE the sed and trip `pipefail`.
toml_value() {
  require_repo
  local key="$1" toml="$REPO_ROOT/tool/lighttool.toml"
  [ -f "$toml" ] || { echo "missing $toml" >&2; exit 1; }
  awk -v key="$key" '
    $0 ~ "^[ \t]*" key "[ \t]*=" {
      if (match($0, /"[^"]*"/))            { print substr($0, RSTART+1, RLENGTH-2); exit }
      if (match($0, /\047[^\047]*\047/))   { print substr($0, RSTART+1, RLENGTH-2); exit }
    }
  ' "$toml"
}

require_pkg() {
  [ -n "$PKG" ] && return 0
  PKG="$(toml_value id)"
  if [ -z "$PKG" ]; then
    echo "Could not read the [tool] id from $REPO_ROOT/tool/lighttool.toml" >&2
    exit 1
  fi
  # The activity class is the SDK's own launcher, identical in every tool —
  # only the package half varies. Do not try to derive it per-tool.
  ACTIVITY="$PKG/com.thelightphone.sdk.LightActivity"
}

# --- helpers ---------------------------------------------------------------
# Single-quote a value for safe interpolation into a REMOTE (device) shell
# command line — `adb shell` joins all its argv into one string and re-parses
# it on-device, so local shell-quoting alone does not protect special
# characters (&, $, ', spaces) in free-form text.
remote_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

require_serial() {
  if [ -z "${ANDROID_SERIAL:-}" ]; then
    echo "ANDROID_SERIAL is not set. List devices with: adb devices -l" >&2
    echo "Then: export ANDROID_SERIAL=<serial>" >&2
    echo "An AVD and a physical LP3 are often both attached; unpinned adb/gradlew" >&2
    echo "either errors on ambiguity or silently targets the wrong device." >&2
    exit 1
  fi
}

# --- commands --------------------------------------------------------------
cmd_build() {
  # build — gradlew :tool:installDebug on $ANDROID_SERIAL.
  #
  # tool/lighttool.toml's serverPackage must match the target, and a mismatch
  # produces NO error at runtime — the tool just binds to a server package that
  # isn't there. The committed value is "com.lightos" (real hardware); AVD work
  # needs a temporary local edit to "com.thelightphone.sdk.emulator", restored
  # with `git checkout -- tool/lighttool.toml`. The check below is advisory
  # only: it prints what it sees and never edits the file, because an
  # invisible-to-`git status` edit is exactly how repos drift.
  require_serial
  require_pkg
  local sp model
  sp="$(toml_value serverPackage)"
  model="$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
  echo "target: ${model:-unknown} ($ANDROID_SERIAL)  package: $PKG  serverPackage: ${sp:-<unset>}"
  case "$ANDROID_SERIAL" in
    emulator-*)
      [ "$sp" = "com.thelightphone.sdk.emulator" ] || echo \
        "WARNING: emulator target but serverPackage='$sp'. Set it to com.thelightphone.sdk.emulator, then restore with 'git checkout -- tool/lighttool.toml'." >&2 ;;
    *)
      [ "$sp" = "com.lightos" ] || echo \
        "WARNING: physical-device target but serverPackage='$sp'. Real hardware needs com.lightos ('git checkout -- tool/lighttool.toml' restores it)." >&2 ;;
  esac
  cd "$REPO_ROOT"
  ./gradlew :tool:installDebug --console=plain
}

cmd_launch() {
  # The SDK shows a generic "loading..." interstitial for ~3s after am start
  # while LightActivity connects to the LightService/RPC — wait it out so the
  # very next screenshot/tap lands on the tool's real UI, not the interstitial.
  require_serial
  require_pkg
  adb shell am start -n "$ACTIVITY"
  sleep 4
}

cmd_killstart() {
  # Hard kill (not backgrounding) + relaunch — the real persistence test.
  require_serial
  require_pkg
  adb shell am force-stop "$PKG"
  sleep 1
  adb shell am start -n "$ACTIVITY"
  sleep 4
}

cmd_screenshot() {
  # screenshot <path> — full PNG via exec-out (no on-device temp file).
  # Relative paths resolve against the caller's cwd: only cmd_build cd's, and
  # it does so as its last act, so nothing here changes directories.
  require_serial
  local out="${1:?usage: driver.sh screenshot <output-path>}"
  sleep 1
  adb exec-out screencap -p > "$out"
  echo "saved: $out"
}

cmd_tap() {
  require_serial
  local x="${1:?x}" y="${2:?y}"
  adb shell "input tap $(remote_quote "$x") $(remote_quote "$y")"
}

cmd_type() {
  require_serial
  local text="${1:?text}"
  adb shell "input text $(remote_quote "$text")"
}

cmd_files() {
  # files [subdir] — list the tool's private files/ dir on device (or a subdir
  # of it, e.g. `files shared/ringtones`). Works because installDebug produces
  # a debuggable APK, which is what lets `run-as` step into its data dir.
  # stderr is folded into stdout so the reason for an empty listing is visible,
  # and `|| true` because "directory doesn't exist yet" is a normal outcome
  # (nothing written yet), not a driver failure.
  require_serial
  require_pkg
  local sub="${1:-}" path="files/"
  if [ -n "$sub" ]; then
    # Normalize to exactly one trailing slash, matching the no-subdir form.
    sub="${sub#/}"
    path="files/${sub%/}/"
  fi
  adb shell "run-as $(remote_quote "$PKG") ls -la $(remote_quote "$path")" 2>&1 || true
}

cmd_uninstall() {
  require_serial
  require_pkg
  adb uninstall "$PKG" || true
}

case "${1:-}" in
  build) cmd_build ;;
  launch) cmd_launch ;;
  killstart) cmd_killstart ;;
  screenshot) shift; cmd_screenshot "$@" ;;
  tap) shift; cmd_tap "$@" ;;
  type) shift; cmd_type "$@" ;;
  files) shift; cmd_files "$@" ;;
  uninstall) cmd_uninstall ;;
  *)
    echo "usage: driver.sh <build|launch|killstart|screenshot|tap|type|files|uninstall> [args...]" >&2
    exit 1
    ;;
esac
