---
id: player-model-rework
title: "Rework the player model"
status: proposed
kind: asset
targets: [read_char_contrast_min]
after: [spike-body-only-humanoid]
phase: C
branch: null
pr: null
updated: 2026-10-02
---
## Goal

The user finds the player model weak up close with the new camera and wants it reworked after the Tripo P2.0 research (now done: P1 stays as-is).

## Scope

- Regenerate per the outcome of `spike-body-only-humanoid` (body-only plus separate clothing, or a better single mesh)
- Fix the known defects: the skirt's skin stretch (3–5× in every clip, accepted for now), skin showing through the tunic (near-coincident vest and body),
  2 open holes and 13 non-manifold edges where the vest meets the tunic, the faint mouth (check faces yourself; the judge misses them), the dark back (L 8–19 albedo; the fill light covers it)
- Paid; the user approves the concept and every spend

## Acceptance

- passes every pipeline stage, the judge and the motion review, with stretch under today's 3–5×
- the user approves it in play

## Serves

`read_char_contrast_min`; the player's look.
