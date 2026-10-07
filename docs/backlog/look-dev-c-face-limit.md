---
id: look-dev-c-face-limit
title: "Look-dev: Tripo v3.1 at a game face_limit (paid, about 55 credits)"
status: proposed
kind: spike
targets: []
after: [spike-target-look]
phase: C
branch: null
pr: null
updated: 2026-10-07
---
## Goal

C at 1.43M triangles only showed over B2 in the face close-up (a rounder jaw, finer hair spikes), and decimating it to 20k broke the UVs and the skin. See whether v3.1 generated at a game budget keeps that shape without the damage.

## Question

Is a v3.1 player at `face_limit` 10,000–20,000 worth about 55 credits (the model 30 as observed for v3.1, the rig 25), from the same approved multiview-1 sheet?

## Options

1. **Run it** at `face_limit` 15,000 (about 55 credits).
2. **Skip it:** stay at B2's mesh with the 1024 px texture.

## Recommendation

Skip it for now unless the face close-up (dialogue distance) is a priority: C's gain over B2 there was small. If it's run, one generation at 15,000 is enough to decide.

## Scope

- `tripo make` with `--model v3.1-20260211 --param texture=true --param pbr=false --param face_limit=<n>` from multiview-1, then the v1.0 rig; through the tripo skill's dry run and confirmation
- built and rendered like C-albedo (`scripts/lookdev/build_c.sh`, `LookDev.tscn`), next to B2 and C-albedo; motion review for idle and run

## Acceptance

- face and body sheets beside B2 and C-albedo, triangles, skin stretch; the user decides whether characters get a higher budget (`docs/trials/look-dev.md` → Variant C, option 2)

## Serves

The art direction, `player-model-rework`.

## Deferred

User, 2026-10-07: don't run it now. Revisit after `spike-target-look` produces new concepts; the concept art, not the model tier, looked like the main limit.
