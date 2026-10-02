---
id: level1-brush-shell
title: "Level 1 ceilings and walls as brush shells"
status: ready
kind: feature
targets: [lvl_interior_ceiling, lvl_bare_wall_run_max]
after: [crypt-trial-textures]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Level 1 has no ceilings; brush shells now provide them.

## Scope

- rebuild Level 1's shell (floors, walls, ceilings) with `brush_boxes.py` layouts and Material Maker tileables, keeping the KayKit detail
- break up long bare walls

## Acceptance

- `lvl_interior_ceiling` present everywhere; `lvl_bare_wall_run_max` ≤ 8 m (16 m today); every replay and clearance check still passes or is re-baselined with reasons

## Serves

`lvl_interior_ceiling`, `lvl_bare_wall_run_max`.
