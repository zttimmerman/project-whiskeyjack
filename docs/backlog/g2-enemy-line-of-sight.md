---
id: g2-enemy-line-of-sight
title: "G2: enemy line of sight, arrows hitting walls, attack tokens"
status: done
kind: feature
targets: [enemy_attackers_max, enc_group_max_first_area]
after: []
phase: gameplay-1
branch: feature/enemy-line-of-sight
pr: 26
updated: 2026-10-01
---
## Goal

Enemies detect only what they can see or hear, and gang up fairly (§3).

## Outcome

A 120° cone plus 4 m hearing, both needing a clear ray (`scripts/combat/WorldRay.gd`); a SEARCH state (last-seen spot, 3.5 s, back to post); `AttackTokens` (2 melee, 1 archer per 2 s); arrows stop at walls. New scenario `tomb_hall_group`.
