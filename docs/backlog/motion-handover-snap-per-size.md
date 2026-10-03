---
id: motion-handover-snap-per-size
title: "Handover snap limit per body height"
status: proposed
kind: chore
targets: []
after: [motion-gates-gait-and-scale]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

`motion_handover_snap_mps` (5 m/s) is still in absolute metres per second. A 4.6 m creature's limbs move about 2.5× faster than a humanoid's in the same pose change, so it will read as snapping where a humanoid wouldn't. Express it in body heights per second, as `motion-gates-gait-and-scale` did for travel, slide and bind deviation (`body_height_m` is already in the metrics; the game-path pass would need it too), keeping humanoid results unchanged.

## Scope

- The game-path pass (`scripts/review/game_path.gd`) reports the snap per body height as well as in m/s
- The art bible's row becomes `motion_handover_snap_bhps` (5 m/s over 1.8 m, rounded up); `judge.py` and `tests/unit/test_anim_blends.gd` follow

## Acceptance

- Humanoid game_path.json files are byte-identical and every handover outcome is unchanged
- The Gobkit boar's handovers are judged per body height

## Serves

The Sett-boar and agent-authored creature clips (`spike-agent-animation` steps 5–6).
