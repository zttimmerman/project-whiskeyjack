---
id: a3-navmesh-bake
title: "A3: edit-time navmesh bake and path-clearance check"
status: done
kind: chore
targets: [lvl_path_clearance_min]
after: []
phase: A
branch: chore/navmesh-bake
pr: 18
updated: 2026-09-30
---
## Goal

Stop baking navmeshes at runtime (§8) and prove the critical path is wide enough. Brief: `docs/plans/phase-a/a3-navmesh-bake.md`.

## Outcome

`scripts/tools/bake_navmeshes.gd` (collision faces, whole-cell agent 2.0/0.5 m); levels no longer bake at runtime, and CI fails a stale bake. `check_path_clearance.gd` reports `lvl_path_clearance_min` from `tests/critical_paths/*.json`. Every segment passes; the narrowest is Level 2 vault → corridor C at 1.5 m. Going `--strict` is `clearance-check-strict`.
