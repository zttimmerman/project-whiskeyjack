---
id: held-prop-tip-check
title: "Check held-prop tip alignment"
status: ready
kind: chore
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Before the player's sword: verify each held prop's tip ends up where the brief's `tip_end` says, in game (godogen idea).

## Scope

- a deterministic check in `make_held_props.gd`'s generator checks or the motion review: the prop's thin end points along the expected axis from the hand socket

## Acceptance

- passes for the Levy Blade and Levy Bow; a deliberately flipped wrapper fails

## Serves

`player-sword`; props alignment (Settled: thinner end at `tip_end`).
