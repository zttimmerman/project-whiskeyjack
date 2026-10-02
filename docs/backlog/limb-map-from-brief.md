---
id: limb-map-from-brief
title: "The motion review picks a rig's limb map from its brief"
status: proposed
kind: chore
targets: []
after: [spike-agent-animation]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

A non-humanoid reviewed without `--limbs` is silently measured with the humanoid map, so its feet read as missing bones. The review should pick the map itself.

## Scope

- a brief field `limb_map: res://data/rigs/<rig>_limbs.tres`; the motion review reads it for `--model`, and fails when the rig lacks the map's bones
- validate checks that every bone in the map resolves

## Acceptance

- the boar's review without `--limbs` measures four feet; humanoid metrics stay byte-identical

## Serves

Non-humanoid enemies (the Sett-boar).
