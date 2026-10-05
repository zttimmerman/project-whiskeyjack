---
id: stagger-starts-cooldown
title: "Stagger cancels the enemy's attack and starts its cooldown"
status: in-review
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/stagger-starts-cooldown
pr: 55
updated: 2026-10-05
---
## Goal

Today stagger skips the cooldown, so an enemy can attack straight after (§3).

## Scope

- stagger cancels the attack and starts the cooldown in `BaseEnemy`

## Acceptance

- a failing gdUnit4 test first (no attack within the cooldown after a stagger)

## Serves

§3 staggers.
