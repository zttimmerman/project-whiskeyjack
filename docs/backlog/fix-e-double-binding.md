---
id: fix-e-double-binding
title: "Resolve the E key's double binding"
status: in-review
kind: fix
targets: []
after: []
phase: gameplay-2
branch: fix/e-double-binding
pr: 44
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

## Decision

User, 2026-10-02: E = `camera_right`; E is removed from `interact`, so F is the only keyboard interact key (interact keeps joypad button 3).
