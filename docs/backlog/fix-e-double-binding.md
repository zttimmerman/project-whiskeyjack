---
id: fix-e-double-binding
title: "Resolve the E key's double binding"
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

E (physical keycode 69) is bound to both `camera_right` and `interact` in `project.godot`.

## Scope

- keep E on one action (F is interact in play today; check §2's layout and the HUD prompts; ask if the intended layout is unclear) and remove the other binding

## Acceptance

- one action per key; dialogue and camera input unchanged otherwise

## Serves

§2 controls; §8 stability.
