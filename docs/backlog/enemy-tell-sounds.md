---
id: enemy-tell-sounds
title: "Tell sounds for enemy windups"
status: proposed
kind: feature
targets: [enemy_melee_telegraph, enemy_ranged_telegraph]
after: []
phase: later
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Decided 2026-10-01: tell sounds wait for the audio pass.

## Scope

- a sound on each melee and ranged tell, through `AudioManager`

## Acceptance

- plays at the tell's start; a playtest for the read

## Serves

`enemy_melee_telegraph`, `enemy_ranged_telegraph`.
