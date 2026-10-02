---
id: render-luminance-checks
title: "Render-based luminance checks in capture mode"
status: ready
kind: chore
targets: [lvl_floor_luminance_min, read_char_contrast_min]
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Measure the two readability targets that are "not measured" or hand-measured (A2b's "later").

## Scope

- in capture mode (Mac, rendered), measure walkable floor luminance from the gameplay camera and character-vs-background contrast
- report per scenario; Linux CI doesn't run it (llvmpipe colours differ)

## Acceptance

- values for Level 1 and the crypt trial, with the method in the PR

## Serves

`lvl_floor_luminance_min`, `read_char_contrast_min`.
