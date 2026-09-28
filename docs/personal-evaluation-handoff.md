---
artifact_contract: "ce-handoff/v1"
created_at: "2026-09-24T07:22:44Z"
title: "Zevra personal evaluation development handoff"
summary: "Continue development of the opt-in personal Jev evaluation from the pushed branch."
keywords: ["zevra", "jev", "personal-evaluation", "handoff"]
resume_focus: "Continue the personal evaluation prototype from PR #3."
repository: "github.com/jaqbec1/zevra"
repo_root_sha: "50c7d18aa02a54fcfbe7ef79f0912cd8058f66da"
branch: "feat/personal-jev"
head: "396c65ca9c319b11c9e4eda1c333361bb4d0d666"
---

# State

This branch implements an opt-in personal Jev evaluation for captured pages. Saved or consumed material is evidence of possible interest, not an endorsement. The app requires explicit ratings before evaluating whether a page is worth attention.

The implementation is in [PR #3](https://github.com/jaqbec1/zevra/pull/3) on `feat/personal-jev`. `macos/Sources/AttentionCore/Personalization.swift` defines candidate import and profile rules. `macos/App/PersonalEvaluation.swift` defines the TypeSafe request, result validation, and local persistence. `macos/App/AppModel.swift` coordinates opt-in evaluation, and `macos/App/AttentionLogApp.swift` exposes setup and per-page correction. `docs/macos-prototype.md` documents the data flow and limits.

The official installed app is still v0.2.0. The branch declares v0.3.0 as a development build; it has not been signed, notarized, released, or installed. Personal evaluation stays off until at least two explicit worthwhile and two explicit not-worthwhile examples, a TypeSafe key, and the separate opt-in are present on the receiving Mac.

# Private data and portability

The app can read a selected Obsidian Base, Markdown folder, structured bookmark or video export, and locally prepared Books title list. Source selection, title-only exports, and any profile draft remain private and are not in Git. Another Mac must obtain them through a private transfer or fresh user selection. Do not infer a broader data-access scope from this public handoff. No live TypeSafe request or measured accuracy trial has been performed.

# Verification and next dependency

The macOS package has 18 passing tests, Swift formatting passes, and an Xcode Debug build succeeds. The repository check previously passed 44 Bun tests, type checking, formatting, extension build, and synthetic demo. GitHub reports no CI checks for this branch. The next product dependency is explicit positive/negative examples and any additional source the user selects. After that, validate request payloads and real classification quality before considering an official 0.3.0 release or installation.
