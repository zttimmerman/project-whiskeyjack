---
id: stagger-starts-cooldown
title: "Stagger cancels the enemy's attack and starts its cooldown"
status: done
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/stagger-starts-cooldown
pr: 55
updated: 2026-10-07
---
## Goal

Today stagger skips the cooldown, so an enemy can attack straight after (§3).

## Scope

- stagger cancels the attack and starts the cooldown in `BaseEnemy`

## Acceptance

- a failing gdUnit4 test first (no attack within the cooldown after a stagger)

## Serves

§3 staggers.

## Decision

User, 2026-10-05 (on PR #55): only a stagger that interrupts an attack (windup or swing) starts the cooldown. A stagger while idle, chasing or searching leaves the cooldown as it was, so steady hits can't stun-lock an enemy.

## Outcome

- `BaseEnemy._change_state(STAGGER)` sets the cooldown to at least `_attack_cooldown()` when the old state was ATTACK (levy 1.5 s, archer 2.0 s).
- Tests: `test_stagger_starts_cooldown` (windup stagger waits out the cooldown) and `test_stagger_while_chasing_keeps_the_cooldown` (the negative case, formerly `..._from_chase`).
- Replays: camera_stress cam_wall_fill 0.427 -> 0.431, cam_melee_occlusion 0.016 -> 0.046; others unchanged.
