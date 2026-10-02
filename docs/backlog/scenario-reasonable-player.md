---
id: scenario-reasonable-player
title: "A \"reasonable player\" 1-on-1 scenario"
status: ready
kind: chore
targets: [enc_first_fight_hp_cost]
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Measure `enc_first_fight_hp_cost` for a player who reacts late to some tells (`levy_1v1_sensible` is a perfect dodger, the skilled ceiling at 0%).

## Scope

- `tests/scenarios/levy_1v1_reasonable.json` (or similar): dodges some tells late, misses one
- seeded and deterministic like the others

## Acceptance

- the scenario runs twice with matching logs and reports `enc_first_fight_hp_cost` against 10–15%
- if it misses, report the value; the tuning is a design decision

## Serves

`enc_first_fight_hp_cost`.
