---
id: decide-gait-thresholds
title: "Confirm the gait check's lift and swing limits"
status: done
kind: decision
targets: []
after: [motion-gates-gait-and-scale]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Set the gait-check minimums for the art bible.

## Question

The gait check (`motion-gates-gait-and-scale`) asserts that in every locomotion clip each foot lifts at least `motion_gait_lift_bh` and swings at least `motion_gait_swing_bh` body heights once per cycle. The scope left the numbers to the user. The package set them as liveness floors from the measured clips: **0.005** lift (9 mm on a 1.8 m humanoid) and **0.05** swing (9 cm).

| Clip | lowest foot lift (bh) | lowest foot swing (bh) |
|---|---|---|
| Player run | 0.198 | 0.632 |
| Front-file run | 0.204 | 0.763 |
| Back-file run (walk) | 0.124 | 0.387 |
| Gobkit boar walk (must pass) | 0.0077 | 0.092 |
| Tripo boar walk, front feet (must fail) | 0.000 | 0.000 |

Keep these numbers, or raise them toward a real step height? Raising lift above about 0.007 fails the Gobkit walk, which the user asked to pass.

## Options

- Keep 0.005 / 0.05: it catches frozen legs only, and slide still catches skating.
- Raise them after the agent-authored clips (spike steps 5–6) show what a good creature walk lifts.

## Recommendation

Keep 0.005 / 0.05 for now: they separate a frozen foot (0) from the weakest real walk (Gobkit, 0.0077 / 0.092) with room on both sides, and every humanoid clears them by 20× or more. Revisit after the agent-authored walk exists.

## Outcome

Decided by the user (2026-10-02): adopt `motion_gait_lift_bh` 0.005 and `motion_gait_swing_bh` 0.05 as minimums (they catch frozen or dragged feet); raise them later if clips pass but still shuffle.
