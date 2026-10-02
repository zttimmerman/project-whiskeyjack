---
id: replay-first-frame-stamp
title: "Fix the replay harness stamping first-frame events 1–2 frames early"
status: ready
kind: fix
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Events on a scenario's first frames carry physics-frame stamps 1–2 frames too early.

## Scope

- find the off-by-one in `EventLog`/`replay.gd` frame counting

## Acceptance

- a failing fixture or test first; baselines updated if they move

## Serves

Every replay-measured target.
