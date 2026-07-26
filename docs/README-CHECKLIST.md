# README checklist

`ci/templates/README.md` is what scaffolding installs into a new tool repo —
`ci/create-tool-repo.sh` does it today, and a future `new-light-tool` skill
will too. Both must point the author back here. As of today, all five
existing tool repos (chess, ledger, ringtone-studio, sudoku, tides) still
open with upstream's "# light-sdk" README and need rewriting.

This README is the first artifact Light's maintainers and the community see —
before anyone opens a source file. Light's stated approval bar is whether a
tool "matches the Light ethos both functionally and aesthetically," and a
README that reads as filled-in boilerplate fails that bar before the code
gets a chance. Write the prose in your own voice; a short, honest paragraph
beats a TODO left in place.

## What it does and who it's for

Why: this is the pitch — a reader should know in one paragraph whether this
tool is for them. What's good: concrete and specific, written for someone
who has never seen the tool; no marketing language, no templated filler.

## Screenshots

Why: LightOS is a monochrome, minimal UI — screenshots are the fastest way to
show a reviewer the tool matches that aesthetic before they build it. What's
good: real device/emulator captures of the actual states a user sees, not
mockups.

## Install (sideload)

Why: most readers won't build from source — this is the path most people
actually use to run the tool. What's good: exact steps, no assumed
familiarity with Android Studio or adb.

## LP3 / LightOS compatibility

Why: readers need to know, without building, whether this runs on their
device/OS. What's good: state what was actually tested (emulator vs.
physical LP3), not what should theoretically work.

## Build from source

Why: this is what a reviewer or contributor actually runs. What's good:
copy-pasteable commands, and the GitHub Packages `read:packages` token
requirement stated explicitly — SDK artifacts don't build without it, and
the SDK README's own property names for it are wrong.

## Attribution

Why: this repo is a derivative of lightphone/light-sdk under its MIT
license — attribution isn't optional politeness, it's a license term.
What's good: a link to lightphone/light-sdk and an explicit statement that
the MIT license is inherited.
