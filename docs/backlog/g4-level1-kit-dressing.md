---
id: g4-level1-kit-dressing
title: "G4: Level 1 in the KayKit dungeon kit"
status: done
kind: feature
targets: [lvl_dressing_density, lvl_light_spacing]
after: []
phase: gameplay-1
branch: feature/level1-kit-dressing
pr: 25
updated: 2026-10-01
---
## Goal

Replace Level 1's blockout with the KayKit Dungeon Remastered kit and dress it.

## Outcome

12 kit pieces at scale 1.0, wrapped in `scenes/world/kit/Kit*.tscn` (StaticBody3D + box/cylinder; the baker reads them), small crates and barrel stacks only, 13 torches. Skirting and plinths are visual-only collision; denser torch spacing accepted.
