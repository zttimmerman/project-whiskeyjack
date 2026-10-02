---
id: anim-blends
title: "Per-transition animation blend times"
status: done
kind: feature
targets: []
after: []
phase: B
branch: feature/anim-blends
pr: 39
updated: 2026-10-02
---
## Goal

Clip handovers stop snapping.

## Outcome

Every handover is under `motion_handover_snap_mps` = 5 m/s, adopted. The user playtested: "way better". The player's skirt skin stretch (3–5× in every clip, pre-existing) is accepted for now; see `player-model-rework`.
