# 00 — Feasibility & Permissibility Assessment — {{LABEL}}

This is a PER-TOOL assessment: does this specific tool clear the SDK's
technical bar and Light's approval bar. The broad cross-tool survey (what's
worth building at all, prioritization across tools) lives in light-workspace,
not here.

## Required capabilities

TODO: what this tool needs from the platform/SDK to function at all —
network, storage, background work, specific permissions, etc.

-

## SDK surface verification

TODO: for each capability above, confirm the SDK actually exposes it and it's
reachable — cite the SDK source file/class verified against, not assumption.
If a capability is only reachable through an unverified or undocumented path,
say so explicitly.

-

## Permission allow-list check

TODO: cross-check every permission this tool will request in
`tool/lighttool.toml` against the SDK's `ALLOWED_PERMISSIONS` list. Anything
not on the list is a blocker, not a request — it doesn't build.

-

## Third-party dependency allow-list check

TODO: cross-check every non-SDK dependency this tool adds against what's
already allowed. Additions require an upstream issue-first request before
use — precedent: upstream issue #40 was accepted and merged as PR #44.

-

## Ethos argument

Light's stated approval bar is whether the tool "matches the Light ethos both
functionally and aesthetically." TODO: make that case for this tool
specifically — finite, no feed, no engagement mechanics, one clear purpose.

## Verdict

TODO: go / no-go, and what (if anything) blocks it.
