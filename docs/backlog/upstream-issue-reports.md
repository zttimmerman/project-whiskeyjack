---
id: upstream-issue-reports
title: "File the upstream issues from the Phase B trials?"
status: needs-user
kind: chore
targets: []
after: []
phase: later
branch: null
pr: null
updated: 2026-10-02
---
## Question

The trials found upstream bugs we patched or worked around: Dialogue Manager patches 1–3 (headless import leak, the `dm` debugger capture on exit, a reference
cycle in `get_line`), Material Maker's CLI ignoring `--size` and segfaulting with `--headless`, and func_godot's cyclic preload. Filing them is public, from the
user's GitHub account. File them?

## Options

1. The agent drafts each issue and files it with `gh` after the user OKs the text.
2. The user files them.
3. Don't file; keep the patches.

## Recommendation

1: each upstream fix shrinks `docs/trials/dialogue-manager-v4.1.0.patch` and the update work.
