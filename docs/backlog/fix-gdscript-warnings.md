---
id: fix-gdscript-warnings
title: "Fix the 10 GDScript warnings in the baseline"
status: ready
kind: chore
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Decided 2026-09-30: tool-script warnings count against §8; fix them in a `chore/` PR.

## Scope

- fix each warning in `ci/warnings-baseline.txt` and delete its line

## Acceptance

- `load_all` logs none of them; the baseline shrinks by 10

## Serves

§8 stability.
