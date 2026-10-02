---
id: g5-enemy-foot-skating
title: "G5: fix the levies' foot skating"
status: done
kind: fix
targets: []
after: []
phase: gameplay-1
branch: fix/enemy-foot-skating
pr: 24
updated: 2026-10-01
---
## Goal

Locomotion clips match ground speed.

## Outcome

The levy is about 13% larger than the Quaternius mannequin, so its clips cover more ground. Front-file chase 4.0 → 4.6 m/s (the user kept it; the player's escape margin is 0.4 m/s), Back-file 1.4 → 1.5. Foot slide 0.21 / 0.17 m/s, enforced by `test_locomotion_foot_slide`. The motion review's foot-slide measurement had a Foot→Toes switching bug, now fixed.
