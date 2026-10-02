---
id: g3-damage-retune
title: "G3: damage ratio, level-band scaling and enemy damage"
status: done
kind: feature
targets: [ttk_levy_player, ttk_player_frontfile, ttk_player_backfile]
after: []
phase: gameplay-1
branch: feature/damage-retune
pr: 23
updated: 2026-09-30
---
## Goal

The settled damage formula and enemy damage share (§6, §11).

## Outcome

`CharacterStats.mitigated_damage` (the ratio), `level_scale` and `scaled_stat` (round to nearest; not yet wired into spawning, see `level-band-spawning`). Enemy attack 14 for both levy variants and arrows (9 HP per hit); `ttk_levy_player` 12.
