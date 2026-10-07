---
id: render-luminance-checks
title: "Render-based luminance checks in capture mode"
status: done
kind: chore
targets: [lvl_floor_luminance_min, read_char_contrast_min]
after: []
phase: gameplay-2
branch: chore/render-luminance-checks
pr: 66
updated: 2026-10-07
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

## Outcome

scripts/review/luminance_probe.gd plus replay.gd --luminance (rendered frames inside the physics step; event logs match headless) and capture_luminance.sh (Mac only). Floor misses: crypt corridor 0.041, L2 tomb hall 0.021 (target 0.05). Player contrast 1.00-1.18 everywhere (target 1.3); levy 1.12-1.28 gameplay view, 1.45-1.70 at 5 m. Question filed as luminance-target-misses. Merged in PR #66.
