---
id: sourced-creature-brief
title: "A brief type for downloaded, already-rigged CC0 creatures"
status: ready
kind: feature
targets: []
after: [sourced-rigged-creatures]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

Let rigged CC0 creatures (like the Gobkit boar, imported as a prop in PR #46) enter the pipeline as creatures: user decision 2026-10-02 (`sourced-rigged-creatures`).

## Scope

- A brief type (e.g. `type: creature` with `source: download`) that keeps the source rig and its clips, skips our rig stage, and validates bones against a limb map (`data/rigs/<rig>_limbs.tres`) instead of SkeletonProfileHumanoid
- The motion review runs on its own clips with that limb map (see `limb-map-from-brief`)
- Humanoid characters still go through our rig flow; sourced humanoids stay refused
- Re-import the Gobkit boar under the new type

## Acceptance

- The boar validates as a creature, its clips run through the motion review with its limb map, and CI's validate job covers it

## Serves

`spike-agent-animation`, the Sett-boar and later creatures.
