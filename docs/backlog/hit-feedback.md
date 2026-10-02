---
id: hit-feedback
title: "Hit flash, enemy health bar, player flinch; no hit effects on dodged hits"
status: proposed
kind: feature
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Every hit reads (§3 feedback, proposed).

## Scope

- hit flash on the target, 0.08–0.12 s
- a health bar on the locked or recently damaged enemy
- a player flinch when hit, 0.2 s, at most one per second
- hit-stop and hit effects never fire on an i-framed hit (today they do)

## Acceptance

- tests first for the flinch limit and the i-framed case
- a playtest for the read

## Serves

§3 feedback on every hit.
