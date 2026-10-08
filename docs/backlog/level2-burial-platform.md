---
id: level2-burial-platform
title: "Make Level 2's 0.5 m burial platform walkable"
status: in-progress
kind: feature
targets: []
after: []
phase: C
branch: feature/level2-platform-steps
pr: null
updated: 2026-10-08
---
## Goal

The user decided (2026-10-08) that Level 2's burial platform is walkable (option 1 of the question below): steps, or an invisible clip ramp under visible steps as on the crypt trial's dais. Until now it stood 0.5 m high, over the navmesh's 0.25 m climb limit, so enemies pathed around it.

Question as asked: is the 0.5 m platform meant to be walkable? Options were 1 walkable (steps or a clip ramp), 2 a set piece as now, 3 lowered to 0.25 m or less; the recommendation was 2 until Level 2 got a brush shell.

## Scope

- Level 2 only, local to the platform: a visible 0.25 m step on its north and south faces and an invisible clip ramp (collision only, 26.6°, the crypt dais's slope) under each, so the player's capsule and the navmesh bake climb the ramp.
- Rebake `scenes/world/Level2_navmesh.tres` with `scripts/tools/bake_navmeshes.gd`.

## Acceptance

- `tests/unit/test_level2_platform.gd`: paths from the vault floor north and south of the platform reach its top on the committed bake, and a player-sized capsule walks over it.
- CI's navmesh job (stale bake, pathfinding, strict path clearance) stays green.

## Serves

Design bible §5 (terraces are the verticality: steps and ramps count) and §8 (edit-time navmesh).
