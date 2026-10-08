---
id: level1-spoke-spacing
title: "Lengthen Level 1's first spoke to 20–60 s between fights"
status: proposed
kind: feature
targets: [enc_spacing_s]
after: [scenario-two-fight-route]
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-07
---
## Goal

`two_fight_route` measures 4.9 s from the Corridor A levy's death to the central room's first swing, against 20–60 s (`enc_spacing_s`). The walk is about 16 m (3 s at 5 m/s) plus the levy's approach and windup. Hitting 20 s needs roughly 75–100 m more route, or exploration (a side room, a payoff in sight, per §4) between the two fights.

## Scope

- a level design decision first (longer corridor, a side room or a payoff detour, or moving the central room's group); proposed until the user picks
- then level geometry, the navmesh rebake and `two_fight_route`'s walk and baseline, dropping `pending`

## Acceptance

- `two_fight_route` reports `enc_spacing_s` in 20–60 s without `pending`

## Serves

`enc_spacing_s`, design bible §4 (rhythm on a spoke).
