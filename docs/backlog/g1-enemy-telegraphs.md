---
id: g1-enemy-telegraphs
title: "G1: enemy attack windups and telegraphs"
status: done
kind: feature
targets: [enemy_melee_telegraph, enemy_ranged_telegraph]
after: []
phase: gameplay-1
branch: feature/enemy-telegraphs
pr: 27
updated: 2026-10-01
---
## Goal

Enemies wind up visibly before attacking, so the player can read and dodge (design bible §3).

## Outcome

Melee 0.6 s (`Sword_Attack`, short hold on the raised blade), archer 0.9 s (`Spell_Simple_Enter`). The timings are constants; clips fit them through `tell`/`contact` markers in `build_animation_library.gd`. A dying enemy's hit no longer lands. `levy_1v1_sensible` is a perfect dodger (0% HP is the skilled ceiling); `ttk_levy_player` lives in `levy_1v1_passive`.
