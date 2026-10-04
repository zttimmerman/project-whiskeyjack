---
id: floor-luminance-b2
title: "Bring Level 2's and the crypt trial's floors up to lvl_floor_luminance_min under B2"
status: proposed
kind: fix
targets: [lvl_floor_luminance_min]
after: [art-rules-b2]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Under the B2 lighting standard (`art-rules-b2`) Level 1's floors pass (minimum 0.051), but Level 2's stay at 0.019 to 0.033 and the crypt trial's corridor and doorway at 0.043 to 0.047, against 0.05 (`scripts/review/level_luminance.tscn`; before B2 they were 0.015 and 0.042). Raising torch energy (1.6 to 2.4) moved them by under 0.01, and ambient 1.1 brought the crypt to 0.050 while flattening the player's contrast to 1.02, so the fix is coverage, not energy.

## Scope

- Level 2: its greybox floor material is albedo 0.18 (linear about 0.03) with six candelabras over 72 m; brighten the greybox floor or add candelabras at the corridors and the vault (visible sources only)
- the crypt trial: torch spacing along the corridor in `crypt_trial.map` (rebuilt with `build_brush_maps.gd`), or a lighter floor ramp only if the art bible's level-side rule is changed
- re-measure every waypoint with `level_luminance.tscn`

## Acceptance

- every critical-path waypoint's floor mean at or above 0.05 in Level 2 and the crypt trial; Level 1 stays in band; replays green

## Serves

`lvl_floor_luminance_min`.
