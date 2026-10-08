---
id: replay-stable-step-order
title: "Apply a scenario's same-frame steps in file order"
status: proposed
kind: fix
targets: []
after: []
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-08
---
## Goal

`scripts/review/replay.gd` sorts a scenario's steps with `sort_custom` on the frame alone, which isn't stable: two steps on one frame (a release and a press of the same action, say) can apply in either order, and the order changes with the number of steps. Found in level1-spoke-spacing: `two_fight_route` released and re-pressed `move_left` on one frame, and the east-aisle leg vanished in runs cut shorter. Each run is still deterministic, so the determinism check doesn't catch it.

## Scope

- Sort by (frame, index in the file), so same-frame steps apply in file order
- A characterization test first (a scenario with a same-frame release and press), then the fix
- Check every scenario's metrics are unchanged

## Acceptance

- Same-frame steps apply in file order whatever the scenario's length; every scenario's baseline holds

## Serves

The replay harness (design bible §10).
