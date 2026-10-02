---
id: player-attack-contact-frames
title: "Measure the player's attack contact frames at the blade's furthest reach"
status: ready
kind: feature
targets: [atk_hitbox_sync]
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Give each player attack clip a `contact` marker, so the hitbox can open on contact instead of on the press.

## Scope

- Contact = the frame of the blade's furthest reach, **measured from our clips** (godogen idea; don't copy their frame counts)
- Markers are written by `scripts/tools/build_animation_library.gd` (the generator), like the enemies' `tell`/`contact` markers
- Re-measure when `player-attack-clips` changes the clips

## Acceptance

- each player attack clip has a contact marker, with the measurement recorded (script output in the PR)
- the library rebuild is deterministic

## Serves

`atk_hitbox_sync`.
