---
id: b3-material-maker
title: "B3: Material Maker palette-locked tileables"
status: done
kind: feature
targets: [lvl_floor_luminance_min]
after: []
phase: B
branch: feature/material-maker-trial
pr: 30
updated: 2026-10-01
---
## Goal

Make level tileables from text `.ptex` graphs, albedo only, palette-locked. Evidence: `docs/trials/material-maker.md`.

## Outcome

Kept: 1.5p1 (`b57f878`) in the gitignored `.tools/`; `scripts/tools/make_textures.py` regenerates `assets/textures/surfaces/` from `.ptex` graphs (Mac only: its renderer needs Vulkan), CI runs `--check`. Dark floors are fixed level-side. Follow-ups: `material-maker-1-7-trial`, `kit-atlas-s3tc-cost`, `upstream-issue-reports`.
