---
id: replay-first-frame-stamp
title: "Fix the replay harness stamping first-frame events 1–2 frames early"
status: done
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/replay-first-frame-stamp
pr: 59
updated: 2026-10-07
---
## Goal

Events on a scenario's first frames carry physics-frame stamps 1–2 frames too early.

## Scope

- find the off-by-one in `EventLog`/`replay.gd` frame counting

## Acceptance

- a failing fixture or test first; baselines updated if they move

## Serves

Every replay-measured target.

## Outcome

PR #59. The runner set the frame origin in its warm-up frame, but it runs last in that frame. So the level's `_ready` and the warm-up frame's gameplay events were stamped as raw counts (0 and 1) and sorted among frames 0–2. The origin is now set before the level enters the tree, so those events stamp -2 and -1. Checked by `tests/scenarios/replay_frame_stamps.json` (a probe level). No scenario baseline moved.
