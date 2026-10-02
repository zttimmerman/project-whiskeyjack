---
id: scenario-two-fight-route
title: "A two-fight route scenario for encounter spacing"
status: ready
kind: chore
targets: [enc_spacing_s]
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Measure walking time between fights on a spoke (about 5–10 s today against 20–60 s).

## Scope

- a scenario that walks a spoke through two fights and reports `enc_spacing_s`

## Acceptance

- runs deterministic; confirms today's value fails the target (scenario-first), so level work has a check

## Serves

`enc_spacing_s`.
