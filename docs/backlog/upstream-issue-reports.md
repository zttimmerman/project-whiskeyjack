---
id: upstream-issue-reports
title: "File the upstream issues from the Phase B trials"
status: ready
kind: chore
targets: []
after: []
phase: later
branch: docs/upstream-issue-drafts
pr: null
updated: 2026-10-08
---
## Goal

File the upstream bugs the Phase B trials patched or worked around, so each upstream fix shrinks `docs/trials/dialogue-manager-v4.1.0.patch` and the update work: Dialogue Manager patches 1–3 (headless import leak, the `dm` debugger capture on exit, a reference cycle in `get_line`), Material Maker's CLI ignoring `--size` and segfaulting with `--headless`, and func_godot's cyclic preload.

**Decided (user, 2026-10-08):** option 1. The agent drafts each issue, the user OKs the text, then the agent files it with `gh` from the user's account. The other options were the user filing them, or not filing and keeping the patches.

## Scope

- **Drafted** in `docs/upstream-issues/` (one file per bug, index in its README), after a read-only duplicate search of each tracker. Five new issues and no comments: Dialogue Manager patch 3 is already fixed on `main` (PR #1303, unreleased), so there's nothing to file for it.
- **Remaining:** file only after the user OKs the drafts. Re-check the Material Maker `--headless` crash on 1.7 before filing it (the draft says how). Then `gh issue create` per draft, record each URL in its draft and trial note, and add a `proposed` item to drop each patch once a release fixes it.

## Acceptance

- The user has OK'd each draft's text (or edited it) in chat.
- Each OK'd draft is filed once; its URL is in the draft and in the trial note that mentions the bug.
- Nothing is filed without that OK.

## Serves

Pin maintenance for the vendored addons and tools (`docs/trials/dialogue-manager.md`, `docs/trials/material-maker.md`, `docs/trials/func-godot.md`).
