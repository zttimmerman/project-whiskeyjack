---
id: player-contrast-b2
title: "Player contrast against corridor backgrounds under B2 (fill light retune)"
status: proposed
kind: fix
targets: [read_char_contrast_min]
after: [art-rules-b2]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Measured from the gameplay camera with `scripts/review/level_luminance.tscn` (linear Rec. 709, (L_hi + 0.05) / (L_lo + 0.05)), the player's back sits at about the luminance of what's behind him in corridors: 1.00 to 1.05 at Level 1's exit, Level 2's corridors and the crypt corridor, before and after B2 (other waypoints 1.25 to 3.5). Enemies all pass under B2 (Level 1 minimum 1.44, Level 2 1.85). The character fill light (`CameraRig/FillLight`, energy 3.5) was tuned under the old lighting with no tonemap.

## Scope

- settle the measurement method in the design bible (`render-luminance-checks`): this ratio, a plain ratio, or a silhouette-edge contrast; the levy's 1.57 and the player's 0.02 were measured differently
- retune the fill light under the filmic tonemap (energy and placement), checking skin clipping in the face close-up
- re-measure with `level_luminance.tscn`

## Acceptance

- `read_char_contrast_min` met at every waypoint, or a design-bible method under which it is; no skin clipping

## Serves

`read_char_contrast_min`.
