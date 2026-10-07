---
id: enemy-corpse-collision
title: "A dead enemy's body stops blocking the player"
status: ready
kind: fix
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-07
---
## Goal

A dead enemy keeps its body collision until it's freed, 2.4 s after death. Found in `two_fight_route`: the Corridor A levy dies 0.8 m in front of the player, who has dodged back against the start room's west wall beside StartCrate5, and pressing forward moves him 0 m for about 2.5 s (frames 453–605) until the corpse is freed. Walking around it works only to the south, between the corpse and the village elder.

## Scope

- turn off the body's collision with the player (layer or shape disabled) the frame the enemy enters DEAD, keeping its floor collision so the death clip stays grounded
- a failing gdUnit4 test first (a dead enemy doesn't block a CharacterBody3D walking through it)
- `two_fight_route` could then walk straight east; its `enc_spacing_s` baseline moves

## Acceptance

- the test passes; replays that kill an enemy have their baselines updated, with the reason given

## Serves

Design bible §3 (death), `enc_spacing_s` measurement.
