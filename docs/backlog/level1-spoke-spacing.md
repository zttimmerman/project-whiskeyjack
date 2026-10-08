---
id: level1-spoke-spacing
title: "Lengthen Level 1's first spoke to 20–60 s between fights"
status: in-progress
kind: feature
targets: [enc_spacing_s]
after: [player-attack-commitment]
phase: gameplay-2
branch: feature/level1-side-room
pr: null
updated: 2026-10-08
---
## Goal

`two_fight_route` measures 4.9 s from the Corridor A levy's death to the central room's first swing, against 20–60 s (`enc_spacing_s`). The walk is about 16 m (3 s at 5 m/s) plus the levy's approach and windup. Hitting 20 s needs roughly 75–100 m more route, or exploration (a side room, a payoff in sight, per §4) between the two fights.

## Scope

- Decided 2026-10-08 (user took the orchestrator's recommendation): a side room off the spoke between Corridor A and the central room, with a payoff in sight from the corridor (a chest or a lore item, per §4 rhythm), so the spacing comes from exploration rather than a longer empty walk. Local to that spoke: no wholesale changes to Level 1
- then level geometry, the navmesh rebake and `two_fight_route`'s walk and baseline, dropping `pending`

## Acceptance

- `two_fight_route` reports `enc_spacing_s` in 20–60 s without `pending`

## Serves

`enc_spacing_s`, design bible §4 (rhythm on a spoke).
