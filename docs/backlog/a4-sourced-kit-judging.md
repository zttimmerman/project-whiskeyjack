---
id: a4-sourced-kit-judging
title: "Judge sourced kits over their UV footprint"
status: done
kind: fix
targets: []
after: []
phase: A
branch: fix/sourced-kit-judging
pr: 19
updated: 2026-09-30
---
## Goal

Make the asset judge fair to sourced kit pieces that share one atlas.

## Outcome

For sourced kits, colour is measured over each piece's UV footprint and may be darkened; the shared atlas is corrected once from the pack's combined footprints (adding a piece re-cleans the pack); holes use `mesh_kit_max_loops_per_part` (2).
