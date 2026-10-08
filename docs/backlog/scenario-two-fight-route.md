---
id: scenario-two-fight-route
title: "A two-fight route scenario for encounter spacing"
status: done
kind: chore
targets: [enc_spacing_s]
after: []
phase: gameplay-2
branch: chore/scenario-two-fight-route
pr: 65
updated: 2026-10-07
---
## Goal

Measure walking time between fights on a spoke (about 5–10 s today against 20–60 s).

## Scope

- a scenario that walks a spoke through two fights and reports `enc_spacing_s`

## Acceptance

- runs deterministic; confirms today's value fails the target (scenario-first), so level work has a check

## Serves

`enc_spacing_s`.

## Outcome

tests/scenarios/two_fight_route.json measures enc_spacing_s = 4.917 s against the 20-60 s target (pending; Level 1's spoke is too short). Found a dead enemy blocking the player until freed. Filed enemy-corpse-collision and level1-spoke-spacing. Merged in PR #65.
