---
id: atk-hitbox-sync
title: "Open the player's hitbox on the clip's contact frame and check it"
status: ready
kind: feature
targets: [atk_hitbox_sync]
after: [player-attack-contact-frames]
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

A swing's hitbox opens within ±2 physics frames of its clip's contact frame (§3).

## Scope

- the hitbox opens on the contact marker, not the press
- wire the `atk_hitbox_sync` check in `replay_metrics.py` and the scenarios

## Acceptance

- the scenario check is added and fails at today's value (opens on the press) before the change, then passes
- `ttk_*` baselines still hold or are updated with reasons

## Serves

§3 hitbox sync.
