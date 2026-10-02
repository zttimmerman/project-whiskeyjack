---
id: phase-c-cc0-kits
title: "More CC0 kits through the import path"
status: ready
kind: asset
targets: [lvl_dressing_density]
after: [import-pack-compress-mode]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Phase C content: dress more spaces from CC0 kits (generate what carries identity, download the rest).

## Scope

- pick packs from `docs/tools-review-2026-09.md`, import through `import_pack.py` with provenance in `assets/sources.json`
- judged at the mesh stage

## Acceptance

- pieces pass clean, validate and the judge; sources complete

## Serves

`lvl_dressing_density`.
