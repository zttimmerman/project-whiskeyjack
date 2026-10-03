---
id: motion-gates-gait-and-scale
title: "Motion gates that catch frozen legs and scale with the creature"
status: ready
kind: chore
targets: []
after: [spike-agent-animation]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The Tripo baseline walk (spike-agent-animation step 3) passes every numeric motion gate although its front legs never move: a frozen foot reads as planted with no slide. And the tolerances are absolute metres (`motion_foot_slide_mps`, `CONTACT_HEIGHT` 0.03 m, bind deviation), so the 1 m Tripo boar passes what the 4.6 m Gobkit boar fails, though per body length both slide alike.

## Scope

- A gait check for locomotion clips: every foot in the limb map lifts and swings at least a set fraction of the body length per cycle (number from the art bible's Judge tolerances, the user's call).
- Foot slide, contact height and bind deviation tolerances relative to the rig's size (body length or hip height) for non-humanoids, with humanoid results unchanged.

## Acceptance

- The Tripo baseline walk fails the gait check (front feet frozen); the Gobkit walk passes it
- Player, Front-file and Back-file motion metrics are byte-identical to before

## Serves

The agent-authored clips' gates (spike-agent-animation steps 5–6) and the Sett-boar.

## Decision

User 2026-10-02: do both before step 4 of `spike-agent-animation`: a gait check (every foot lifts and swings in walk/run clips) and slide limits relative to body size, calibrated so humanoid results are unchanged (an art-bible tolerance change).
