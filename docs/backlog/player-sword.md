---
id: player-sword
title: "Generate the player's sword"
status: proposed
kind: asset
targets: []
after: [held-prop-tip-check, decide-player-sword]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The player gets his own sword instead of the Levy Blade.

## Scope

- through the asset pipeline and tripo skill, on the model `decide-player-sword` picks; held via a generated `Held*.tscn` wrapper

## Acceptance

- passes every stage, the judge and the tip check

## Serves

The player's look; `player-attack-contact-frames` re-measured if the blade length changes.
