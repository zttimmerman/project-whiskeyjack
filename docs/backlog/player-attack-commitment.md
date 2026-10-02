---
id: player-attack-commitment
title: "Attacks commit: movement locked during swings, lunge to a locked target"
status: ready
kind: feature
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
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
