---
id: tooling-hardening
title: "Harden tooling: timeouts, game-path motion review, checked generators"
status: done
kind: chore
targets: []
after: []
phase: B
branch: chore/tooling-hardening
pr: 38
updated: 2026-10-02
---
## Goal

Ideas from the godogen review: nothing hangs, and motion is reviewed the way the game plays it.

## Outcome

Timeouts on every Godot/Blender call (`scripts/tools/godot_timeout.*`), a game-path motion review, and generator checks (`scripts/tools/generator_checks.gd`); the held-prop generator was non-deterministic and now isn't.
