---
id: attack-token-handoff-delay
title: "Delay the attack-token hand-off when a holder dies"
status: ready
kind: fix
targets: [enemy_attackers_max]
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The attack-token hand-off on death is immediate, so a 2 s window can briefly count 3 attackers.

## Scope

- hand the token on after a short delay (or count the dying holder until its window ends) in `AttackTokens`

## Acceptance

- a failing test first: no 2 s window counts more than the limit when a holder dies

## Serves

`enemy_attackers_max`.
