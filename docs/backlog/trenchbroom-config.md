---
id: trenchbroom-config
title: "Set up TrenchBroom and test the .map round-trip"
status: proposed
kind: chore
targets: []
after: []
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Let the user edit brush maps in TrenchBroom (func_godot follow-up 3).

## Scope

- install TrenchBroom (GPL, free; needs the user's OK to install), export the game config, and show `clip`/`skip` textures
- round-trip `crypt_trial.map`; once a map is edited in TrenchBroom, the `.map` becomes the source and its layout file is deleted

## Acceptance

- the crypt trial opens, saves and rebuilds identically apart from TrenchBroom's comment rewrite

## Serves

`b2-func-godot`.
