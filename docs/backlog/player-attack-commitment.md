---
id: player-attack-commitment
title: "Attacks commit: movement locked during swings, lunge to a locked target"
status: in-review
kind: feature
targets: []
after: []
phase: gameplay-2
branch: feature/player-attack-commitment
pr: 64
updated: 2026-10-07
---
## Goal

The settled attack commitment (§3, §11.3).

## Scope

- movement is locked for the swing
- a short forward lunge (0.3–0.5 m) toward a locked target
- a dodge can cancel an attack only after its active frames

## Acceptance

- failing gdUnit4 tests first (lock, lunge distance range, cancel window)
- replay baselines updated where they move

## Serves

§3 attacks commit; §11 decision 3.

## Outcome

Movement locks for the attack clip (light 0.43 s, heavy 2.0 s), a 0.4 m lunge toward a locked target over the active frames, and a dodge cancels only after the active frames. Tests in test_attack_commitment.gd; camera baselines in camera_stress and levy_1v1_sensible moved slightly. Heavy lock length is open (heavy-swing-lock-length). PR #64.
