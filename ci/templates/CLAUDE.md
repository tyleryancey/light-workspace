# CLAUDE.md — {{LABEL}} (Light Phone 3 tool)

TODO: one or two sentences — what this tool does, and why it's worth building on the SDK.

**Division of labor:** this doc is the plan of record; Claude Code owns compile–run–debug. SDK source outranks this doc.

## Purpose

TODO: who this is for, what gap it fills, why it belongs on the Light Phone 3.

## Verified SDK facts this tool relies on

TODO: SDK APIs and behavior you've confirmed by reading SDK source or running code — not assumptions. Name the example module you're modeling on, if any.

-

## lighttool.toml

```toml
[tool]
id            = "{{ID}}"
label         = "{{LABEL}}"
versionCode   = 1
versionName   = "0.1.0"
permissions   = []
serverPackage = "com.lightos"
```

## Architecture

TODO: module/file layout — one line per file on what it owns.

## Behavior

TODO: screen-by-screen — what the user sees and does.

## Milestones · definitions of done

TODO: phased plan; each phase ends in a concrete, checkable "done" state.

## Vetting defense (seed)

TODO: one paragraph arguing this tool matches the Light ethos — finite, no feed, no dark patterns, one clear purpose.

## Sharp edges

- Gradle needs GitHub Packages credentials as `GH_PACKAGES_USER`/`GH_PACKAGES_TOKEN` env vars, or `gpr.user`/`gpr.key` in `local.properties` — the SDK README's own property names for these are wrong.
- `serverPackage` must stay `com.lightos` in commits: Light's builder compiles the committed value, so an emulator value produces an APK that cannot bind to LightOS on real hardware. Flip it locally for AVD work, then restore with `git checkout -- tool/lighttool.toml` before committing.
-
