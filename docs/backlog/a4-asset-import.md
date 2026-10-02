---
id: a4-asset-import
title: "A4: downloaded-asset import path"
status: done
kind: feature
targets: [lvl_dressing_density]
after: []
phase: A
branch: feature/asset-import-path
pr: 16
updated: 2026-09-30
---
## Goal

CC0 kits go through the same clean stage as generated assets and land in the same colour space and shading standard (generate what carries identity, download the rest). Brief: `docs/plans/phase-a/a4-asset-import.md`.

## Outcome

CC0 kits go through `scripts/tools/import_pack.py` into the gitignored `.downloads/`, with provenance in `assets/sources.json` (CC0 only, checked by validate). Six KayKit Dungeon Remastered pieces pass the judge. This was the "pipeline path for downloaded CC0 assets" queued in `docs/decisions.md`.
